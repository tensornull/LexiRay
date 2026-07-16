import Foundation

private struct AlphaBitmap {
  let width: Int
  let height: Int
  var pixels: [Double]

  init(width: Int, height: Int, fill: Double = 0) {
    self.width = width
    self.height = height
    pixels = [Double](repeating: fill, count: width * height)
  }

  subscript(x: Int, y: Int) -> Double {
    get { pixels[y * width + x] }
    set { pixels[y * width + x] = newValue }
  }
}

private func roundedPanel(width: Int, height: Int, radius: Int) -> AlphaBitmap {
  var bitmap = AlphaBitmap(width: width, height: height, fill: 1)
  for y in 0 ..< radius {
    for x in 0 ..< radius {
      let dx = Double(radius - x)
      let dy = Double(radius - y)
      if dx * dx + dy * dy > Double(radius * radius) {
        bitmap[x, y] = 0
        bitmap[width - 1 - x, y] = 0
      }
    }
  }
  return bitmap
}

private func menuCapture(from reference: AlphaBitmap, height: Int) -> AlphaBitmap {
  var bitmap = AlphaBitmap(width: reference.width, height: height)
  for y in 0 ..< reference.height {
    for x in 0 ..< reference.width {
      bitmap[x, y] = reference[x, y]
    }
  }
  for y in reference.height ..< height {
    for x in 32 ..< 96 {
      bitmap[x, y] = 1
    }
  }
  return bitmap
}

private func analyze(reference: AlphaBitmap, menu: AlphaBitmap) throws -> PanelMenuBorderAnalysis {
  try analyzePanelMenuOpenBorder(
    referenceWidth: reference.width,
    referenceHeight: reference.height,
    menuOpenWidth: menu.width,
    menuOpenHeight: menu.height,
    referenceAlphaAt: { reference[$0, $1] },
    menuOpenAlphaAt: { menu[$0, $1] }
  )
}

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
  guard condition() else {
    fputs("PANEL_BORDER_EVIDENCE_TEST_FAIL: \(message)\n", stderr)
    exit(1)
  }
}

@main
private enum PanelBorderEvidenceTest {
  static func main() throws {
    let reference = roundedPanel(width: 128, height: 72, radius: 28)

    let clean = menuCapture(from: reference, height: 128)
    let cleanAnalysis = try analyze(reference: reference, menu: clean)
    expect(cleanAnalysis.leakingCorners.isEmpty, "clean corner failed")

    var noisy = clean
    for y in stride(from: 0, through: 20, by: 5) {
      noisy[127, y] = 0.12
    }
    for x in stride(from: 108, through: 127, by: 5) {
      noisy[x, 0] = 0.12
    }
    let noisyAnalysis = try analyze(reference: reference, menu: noisy)
    expect(
      noisyAnalysis.leakingCorners.isEmpty,
      "isolated antialias/noise pixels caused a false positive"
    )

    var horizontalLeak = clean
    for x in 104 ..< 128 {
      horizontalLeak[x, 0] = 0.12
    }
    let horizontalAnalysis = try analyze(reference: reference, menu: horizontalLeak)
    expect(
      !horizontalAnalysis.leakingCorners.isEmpty,
      "faint horizontal rectangular hairline was accepted"
    )

    var verticalLeak = clean
    for y in 0 ..< 24 {
      verticalLeak[127, y] = 0.08
    }
    let verticalAnalysis = try analyze(reference: reference, menu: verticalLeak)
    expect(
      !verticalAnalysis.leakingCorners.isEmpty,
      "faint vertical rectangular hairline was accepted"
    )

    do {
      _ = try analyze(reference: reference, menu: reference)
      expect(false, "capture without an attached menu was accepted")
    } catch let error as PanelMenuBorderAnalysisError {
      expect(
        error.description.contains("does not include the attached language menu"),
        "wrong missing-menu failure: \(error)"
      )
    }

    print("PANEL_BORDER_EVIDENCE_TEST_PASS")
  }
}
