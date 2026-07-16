import Foundation

struct PanelCornerBorderMetrics: Equatable {
  let corner: String
  let exteriorPixelCount: Int
  let unexpectedPixelCount: Int
  let longestHorizontalRun: Int
  let longestVerticalRun: Int

  var longestRun: Int {
    max(longestHorizontalRun, longestVerticalRun)
  }
}

struct PanelMenuBorderAnalysis: Equatable {
  let referenceSize: (width: Int, height: Int)
  let menuOpenSize: (width: Int, height: Int)
  let sampleSpan: Int
  let minimumLeakRun: Int
  let corners: [PanelCornerBorderMetrics]

  static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.referenceSize.width == rhs.referenceSize.width
      && lhs.referenceSize.height == rhs.referenceSize.height
      && lhs.menuOpenSize.width == rhs.menuOpenSize.width
      && lhs.menuOpenSize.height == rhs.menuOpenSize.height
      && lhs.sampleSpan == rhs.sampleSpan
      && lhs.minimumLeakRun == rhs.minimumLeakRun
      && lhs.corners == rhs.corners
  }

  var leakingCorners: [PanelCornerBorderMetrics] {
    corners.filter { $0.longestRun >= minimumLeakRun }
  }

  var evidenceText: String {
    var lines = [
      "reference_size=\(referenceSize.width)x\(referenceSize.height)",
      "menu_open_size=\(menuOpenSize.width)x\(menuOpenSize.height)",
      "sample_span=\(sampleSpan)",
      "minimum_leak_run=\(minimumLeakRun)",
      "alpha_baseline_max=0.01",
      "alpha_unexpected_min=0.04",
      "alpha_delta_min=0.03"
    ]
    for corner in corners {
      lines.append(
        "corner=\(corner.corner),exterior_pixels=\(corner.exteriorPixelCount),"
          + "unexpected_pixels=\(corner.unexpectedPixelCount),"
          + "longest_horizontal_run=\(corner.longestHorizontalRun),"
          + "longest_vertical_run=\(corner.longestVerticalRun)"
      )
    }
    lines.append("result=\(leakingCorners.isEmpty ? "clean" : "leaked")")
    return lines.joined(separator: "\n")
  }
}

enum PanelMenuBorderAnalysisError: Error, CustomStringConvertible {
  case invalidLayout(String)
  case unreadablePixel(String)

  var description: String {
    switch self {
    case let .invalidLayout(message), let .unreadablePixel(message):
      message
    }
  }
}

private func longestDenseRun(_ values: [Bool]) -> Int {
  var best = 0
  var start = 0
  var falseCount = 0

  for end in values.indices {
    if !values[end] {
      falseCount += 1
    }
    while falseCount > 1, start <= end {
      if !values[start] {
        falseCount -= 1
      }
      start += 1
    }
    best = max(best, end - start + 1 - falseCount)
  }
  return best
}

func analyzePanelMenuOpenBorder(
  referenceWidth: Int,
  referenceHeight: Int,
  menuOpenWidth: Int,
  menuOpenHeight: Int,
  referenceAlphaAt: (Int, Int) -> Double?,
  menuOpenAlphaAt: (Int, Int) -> Double?
) throws -> PanelMenuBorderAnalysis {
  guard referenceWidth >= 64, referenceHeight >= 64 else {
    throw PanelMenuBorderAnalysisError.invalidLayout(
      "reference panel bitmap is too small for rounded-corner evidence"
    )
  }
  guard menuOpenWidth == referenceWidth else {
    throw PanelMenuBorderAnalysisError.invalidLayout(
      "menu-open bitmap width \(menuOpenWidth) does not preserve panel width \(referenceWidth)"
    )
  }
  let minimumMenuExtension = max(8, referenceHeight / 20)
  guard menuOpenHeight >= referenceHeight + minimumMenuExtension else {
    throw PanelMenuBorderAnalysisError.invalidLayout(
      "menu-open bitmap does not include the attached language menu "
        + "(reference \(referenceHeight), menu-open \(menuOpenHeight))"
    )
  }

  let sampleSpan = min(64, referenceWidth / 4, referenceHeight / 4)
  let minimumLeakRun = max(8, sampleSpan / 6)
  let baselineMaximum = 0.01
  let unexpectedMinimum = 0.04
  let minimumDelta = 0.03
  var metrics: [PanelCornerBorderMetrics] = []

  for (name, xOffset) in [("top-left", 0), ("top-right", referenceWidth - sampleSpan)] {
    var unexpected = [Bool](repeating: false, count: sampleSpan * sampleSpan)
    var exteriorPixelCount = 0
    var unexpectedPixelCount = 0

    for y in 0 ..< sampleSpan {
      for localX in 0 ..< sampleSpan {
        let x = xOffset + localX
        guard let referenceAlpha = referenceAlphaAt(x, y),
              let menuOpenAlpha = menuOpenAlphaAt(x, y)
        else {
          throw PanelMenuBorderAnalysisError.unreadablePixel(
            "could not read \(name) pixel at (\(x), \(y))"
          )
        }
        guard referenceAlpha <= baselineMaximum else {
          continue
        }
        exteriorPixelCount += 1
        let leaked = menuOpenAlpha >= unexpectedMinimum
          && menuOpenAlpha - referenceAlpha >= minimumDelta
        unexpected[y * sampleSpan + localX] = leaked
        if leaked {
          unexpectedPixelCount += 1
        }
      }
    }

    guard exteriorPixelCount >= sampleSpan else {
      throw PanelMenuBorderAnalysisError.invalidLayout(
        "reference \(name) does not expose enough transparent rounded-corner pixels"
      )
    }

    let longestHorizontalRun = (0 ..< sampleSpan).map { y in
      let start = y * sampleSpan
      return longestDenseRun(Array(unexpected[start ..< start + sampleSpan]))
    }.max() ?? 0
    let longestVerticalRun = (0 ..< sampleSpan).map { x in
      longestDenseRun((0 ..< sampleSpan).map { y in unexpected[y * sampleSpan + x] })
    }.max() ?? 0

    metrics.append(
      PanelCornerBorderMetrics(
        corner: name,
        exteriorPixelCount: exteriorPixelCount,
        unexpectedPixelCount: unexpectedPixelCount,
        longestHorizontalRun: longestHorizontalRun,
        longestVerticalRun: longestVerticalRun
      )
    )
  }

  return PanelMenuBorderAnalysis(
    referenceSize: (referenceWidth, referenceHeight),
    menuOpenSize: (menuOpenWidth, menuOpenHeight),
    sampleSpan: sampleSpan,
    minimumLeakRun: minimumLeakRun,
    corners: metrics
  )
}
