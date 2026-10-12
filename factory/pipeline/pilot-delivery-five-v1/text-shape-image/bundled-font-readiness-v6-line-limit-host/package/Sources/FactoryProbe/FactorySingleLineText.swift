import Foundation
import SwiftRightBridge

struct FactorySingleLineTextSelection {
    let displayText: String
    let measurement: TextMeasurement
    let candidateCount: Int
}

enum FactorySingleLineTextError: Error {
    case sourceTooLong
    case invalidWidth
    case multilineWithoutBound
    case noCandidateFits
}

/// Selects longest fitting prefix plus ellipsis for one-line bounded text.
/// Every rejected bridge measurement is released by `release`; only returned run
/// remains owned by caller. Search is logarithmically bounded for long strings.
func factorySelectSingleLineText(
    _ text: String,
    maxWidth: Float,
    measure: (_ candidate: String) throws -> TextMeasurement,
    release: (_ run: TextRunHandle) -> Void
) throws -> FactorySingleLineTextSelection {
    guard maxWidth.isFinite, maxWidth >= 0 else {
        throw FactorySingleLineTextError.invalidWidth
    }
    // Bound traversal & allocation before materializing grapheme clusters.
    let boundedText = String(text.prefix(4097))
    guard boundedText.count <= 4096 else {
        throw FactorySingleLineTextError.sourceTooLong
    }
    let characters = Array(boundedText)
    var evaluations = 0
    let maxEvaluations = 128

    func candidate(_ prefixCount: Int) -> String {
        String(characters.prefix(prefixCount)) + "…"
    }
    func evaluate(_ value: String) throws -> TextMeasurement? {
        guard evaluations < maxEvaluations else { return nil }
        evaluations += 1
        let result = try measure(value)
        let fits = result.lineCount == 1 && (maxWidth <= 0 || result.width <= maxWidth)
        if fits { return result }
        release(result.run)
        return nil
    }

    let original = try measure(text)
    evaluations += 1
    if original.lineCount == 1 && (maxWidth <= 0 || original.width <= maxWidth) {
        return FactorySingleLineTextSelection(displayText: text, measurement: original,
                                              candidateCount: evaluations)
    }
    release(original.run)
    guard maxWidth > 0 else { throw FactorySingleLineTextError.multilineWithoutBound }
    guard !characters.isEmpty else { throw FactorySingleLineTextError.noCandidateFits }

    var low = 0
    var high = max(0, characters.count - 1)
    var best: (prefixCount: Int, measurement: TextMeasurement)?
    do {
        while low <= high && evaluations < maxEvaluations {
            let middle = low + (high - low) / 2
            if let result = try evaluate(candidate(middle)) {
                if let old = best { release(old.measurement.run) }
                best = (middle, result)
                low = middle + 1
            } else {
                high = middle - 1
            }
        }
    } catch {
        if let best { release(best.measurement.run) }
        throw error
    }
    guard let best else { throw FactorySingleLineTextError.noCandidateFits }
    return FactorySingleLineTextSelection(displayText: candidate(best.prefixCount),
                                          measurement: best.measurement,
                                          candidateCount: evaluations)
}
