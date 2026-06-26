/** \file
 * @brief Time sync batch mode implementation - query multiple strong stations
 * for time validation and outlier detection
 */

#include "JS8_UI/mainwindow.h"
#include <QTimer>
#include <QDateTime>
#include <algorithm>
#include <cmath>

/**
 * @brief Get the top N stations by SNR from recent call activity
 * @param count Number of top stations to return
 * @return List of CallDetail sorted by SNR (strongest first)
 */
QList<UI_Constructor::CallDetail> UI_Constructor::getTopStationsBySnr(int count)
{
    // Collect all recent call activity
    QList<CallDetail> allCalls;
    
    // Iterate through all bands in call activity cache
    for (auto bandIt = m_callActivityBandCache.begin();
         bandIt != m_callActivityBandCache.end(); ++bandIt)
    {
        for (auto callIt = bandIt.value().begin();
             callIt != bandIt.value().end(); ++callIt)
        {
            allCalls.append(callIt.value());
        }
    }
    
    // Sort by SNR (strongest first)
    std::sort(allCalls.begin(), allCalls.end(),
              [](const CallDetail &a, const CallDetail &b) {
                  return a.snr > b.snr;
              });
    
    // Return top N, or all if fewer than N available
    return allCalls.mid(0, std::min(count, allCalls.count()));
}

/**
 * @brief Initiate a batch time sync query to the top N stations by signal strength
 * @param targetCount Number of stations to query (3-5 recommended)
 */
void UI_Constructor::startTimeSyncBatchQuery(int targetCount)
{
    auto topStations = getTopStationsBySnr(targetCount);
    
    if (topStations.isEmpty())
    {
        writeNoticeTextToUI(DriftingDateTime::currentDateTimeUtc(),
                            "No stations heard yet - cannot start batch time sync");
        return;
    }
    
    // Initialize batch mode
    m_timeSyncBatch.active = true;
    m_timeSyncBatch.targetCount = std::min(targetCount, topStations.count());
    m_timeSyncBatch.responses.clear();
    m_timeSyncBatch.started = DriftingDateTime::currentDateTimeUtc();
    
    // Setup timeout timer (30 seconds to collect responses)
    if (!m_timeSyncBatch.timeoutTimer)
    {
        m_timeSyncBatch.timeoutTimer = new QTimer(this);
        connect(m_timeSyncBatch.timeoutTimer, &QTimer::timeout,
                this, &UI_Constructor::onTimeSyncBatchTimeout);
    }
    m_timeSyncBatch.timeoutTimer->start(30000); // 30 seconds
    
    // Build list of station names for user notification
    QString stationList;
    for (int i = 0; i < topStations.count(); ++i)
    {
        if (i > 0) stationList += ", ";
        stationList += QString("%1 (%2dB)")
                           .arg(topStations[i].call)
                           .arg(Varicode::formatSNR(topStations[i].snr));
    }
    
    writeNoticeTextToUI(DriftingDateTime::currentDateTimeUtc(),
                        QString("Starting batch time sync with top %1 stations: %2")
                            .arg(m_timeSyncBatch.targetCount)
                            .arg(stationList));
    
    // Send TIME? queries to each station
    for (const auto &station : topStations)
    {
        auto const t1 = DriftingDateTime::currentMSecsSinceEpoch();
        auto const rid = QString::number((quint64)t1, 36).right(8).toUpper();
        
        // Track this request
        m_timeSyncPending.insert(
            rid, {station.call, t1, DriftingDateTime::currentDateTimeUtc()});
        
        // Enqueue directed message
        addMessageText(QString("%1 QUERY TIME? RID %2 T1 %3 BATCH")
                           .arg(station.call)
                           .arg(rid)
                           .arg(t1),
                       false); // Don't show in message box, add silently
    }
    
    // Transmit all queued messages
    if (m_config.transmit_directed())
        toggleTx(true);
}

/**
 * @brief Handle batch timeout - validate and apply responses collected so far
 */
void UI_Constructor::onTimeSyncBatchTimeout()
{
    if (m_timeSyncBatch.timeoutTimer)
        m_timeSyncBatch.timeoutTimer->stop();
    
    validateAndApplyTimeSyncBatch();
}

/**
 * @brief Validate collected time sync responses and apply consensus offset
 * Uses median-based outlier rejection to identify bad actors/broken clocks
 */
void UI_Constructor::validateAndApplyTimeSyncBatch()
{
    if (m_timeSyncBatch.responses.isEmpty())
    {
        writeNoticeTextToUI(DriftingDateTime::currentDateTimeUtc(),
                            "Batch time sync: no responses received");
        m_timeSyncBatch.active = false;
        return;
    }
    
    auto responses = m_timeSyncBatch.responses.values();
    int responseCount = responses.count();
    
    // Calculate median offset
    std::sort(responses.begin(), responses.end());
    int medianOffset =
        (responseCount % 2 == 0)
            ? (responses[responseCount / 2 - 1] + responses[responseCount / 2]) / 2
            : responses[responseCount / 2];
    
    // Reject outliers that differ from median by more than 1 second
    constexpr int OUTLIER_THRESHOLD_MS = 1000;
    QList<int> validOffsets;
    
    for (int offset : responses)
    {
        if (std::abs(offset - medianOffset) <= OUTLIER_THRESHOLD_MS)
        {
            validOffsets.append(offset);
        }
    }
    
    int rejectedCount = responseCount - validOffsets.count();
    
    if (validOffsets.isEmpty())
    {
        writeNoticeTextToUI(
            DriftingDateTime::currentDateTimeUtc(),
            QString("Batch time sync: all %1 responses were outliers - "
                    "possible bad actors on channel")
                .arg(responseCount));
        m_timeSyncBatch.active = false;
        return;
    }
    
    // Average the valid offsets
    qint64 sumOffset = 0;
    for (int offset : validOffsets)
        sumOffset += offset;
    int averageOffset = (int)std::round((double)sumOffset / validOffsets.count());
    
    // Apply the offset to our clock
    auto currentDrift = DriftingDateTime::getDrift();
    auto newDrift = currentDrift + averageOffset;
    auto oldDrift = currentDrift;
    
    DriftingDateTime::setDrift(newDrift);
    
    // Report results to user
    QString report = QString(
        "Batch time sync complete:\n"
        "  Responses: %1 received, %2 valid, %3 rejected as outliers\n"
        "  Median offset: %4 ms, Average: %5 ms\n"
        "  Clock correction: %6 ms → %7 ms (Δ %8 ms)")
        .arg(responseCount)
        .arg(validOffsets.count())
        .arg(rejectedCount)
        .arg(medianOffset)
        .arg(averageOffset)
        .arg(oldDrift)
        .arg(newDrift)
        .arg(averageOffset);
    
    writeNoticeTextToUI(DriftingDateTime::currentDateTimeUtc(), report);
    
    m_timeSyncBatch.active = false;
}
