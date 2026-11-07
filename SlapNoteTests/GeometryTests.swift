import CoreGraphics
import XCTest
@testable import SlapNoteCore

final class GeometryTests: XCTestCase {
    func testProportionalResizeScalesFontBySameFactor() {
        let r = NoteGeometry.resize(size: CGSize(width: 200, height: 100), fontScale: 1, factor: 1.5, mode: .proportional)
        XCTAssertEqual(r.size.width, 300, accuracy: 0.001)
        XCTAssertEqual(r.size.height, 150, accuracy: 0.001)
        XCTAssertEqual(r.fontScale, 1.5, accuracy: 0.001)
        XCTAssertFalse(r.hitLimit)
    }

    func testProportionalResizeKeepsAspectAtMaximum() {
        let r = NoteGeometry.resize(size: CGSize(width: 400, height: 200), fontScale: 1, factor: 2, mode: .proportional)
        XCTAssertEqual(r.size.width, 600, accuracy: 0.001)
        XCTAssertEqual(r.size.height, 300, accuracy: 0.001)
        XCTAssertEqual(r.fontScale, 1.5, accuracy: 0.001, "font scales with the clamped factor")
        XCTAssertTrue(r.hitLimit)
    }

    func testProportionalResizeKeepsAspectAtMinimum() {
        let r = NoteGeometry.resize(size: CGSize(width: 100, height: 200), fontScale: 1, factor: 0.5, mode: .proportional)
        XCTAssertEqual(r.size.width, 80, accuracy: 0.001)
        XCTAssertEqual(r.size.height, 160, accuracy: 0.001)
        XCTAssertTrue(r.hitLimit)
    }

    func testWidthOnlyLeavesHeightAndFont() {
        let r = NoteGeometry.resize(size: CGSize(width: 200, height: 200), fontScale: 1.2, factor: 1.1, mode: .widthOnly)
        XCTAssertEqual(r.size.width, 220, accuracy: 0.001)
        XCTAssertEqual(r.size.height, 200)
        XCTAssertEqual(r.fontScale, 1.2)
    }

    func testHeightOnlyClampsToLimits() {
        let up = NoteGeometry.resize(size: CGSize(width: 200, height: 590), fontScale: 1, factor: 1.2, mode: .heightOnly)
        XCTAssertEqual(up.size.height, 600)
        XCTAssertTrue(up.hitLimit)
        let down = NoteGeometry.resize(size: CGSize(width: 200, height: 85), fontScale: 1, factor: 0.5, mode: .heightOnly)
        XCTAssertEqual(down.size.height, 80)
        XCTAssertTrue(down.hitLimit)
    }

    func testInvalidFactorIsIgnored() {
        let r = NoteGeometry.resize(size: CGSize(width: 200, height: 200), fontScale: 1, factor: .nan, mode: .proportional)
        XCTAssertEqual(r.size, CGSize(width: 200, height: 200))
    }

    func testShapeSwitchKeepsWidthAndUsesShapeAspect() {
        let s = NoteGeometry.size(switchingTo: .rectangle, from: CGSize(width: 280, height: 280))
        XCTAssertEqual(s.width, 280)
        XCTAssertEqual(s.height, 190, accuracy: 0.5)
    }

    // MARK: Auto-grow

    func testAutoGrowKeepsManualHeightWhenTextFits() {
        let r = AutoGrow.displayedHeight(manualHeight: 220, textHeight: 40, shape: .square, padding: 8, visibleScreenHeight: 900)
        XCTAssertEqual(r.height, 220)
        XCTAssertFalse(r.needsInternalScrolling)
    }

    func testAutoGrowGrowsInHeightForEveryShape() {
        for shape in NoteShape.allCases {
            let r = AutoGrow.displayedHeight(manualHeight: 200, textHeight: 400, shape: shape, padding: 8, visibleScreenHeight: 2000)
            XCTAssertGreaterThan(r.height, 200, "\(shape)")
            let textArea = shape.safeTextRect(in: CGRect(x: 0, y: 0, width: 200, height: r.height)).height - 16
            XCTAssertGreaterThanOrEqual(textArea, 399.5, "text must fit inside the safe area of \(shape)")
            XCTAssertFalse(r.needsInternalScrolling)
        }
    }

    func testAutoGrowMayExceedManualMaximumButNotScreen() {
        let r = AutoGrow.displayedHeight(manualHeight: 300, textHeight: 700, shape: .square, padding: 8, visibleScreenHeight: 1000)
        XCTAssertGreaterThan(r.height, 600, "auto-grow can exceed the 600 pt manual maximum")
        XCTAssertLessThanOrEqual(r.height, 960)
        let capped = AutoGrow.displayedHeight(manualHeight: 300, textHeight: 5000, shape: .square, padding: 8, visibleScreenHeight: 1000)
        XCTAssertEqual(capped.height, 960)
        XCTAssertTrue(capped.needsInternalScrolling)
    }

    func testAutoGrowShrinksBackButNotBelowManualHeight() {
        let grown = AutoGrow.displayedHeight(manualHeight: 250, textHeight: 500, shape: .circle, padding: 8, visibleScreenHeight: 1200)
        XCTAssertGreaterThan(grown.height, 250)
        let shrunk = AutoGrow.displayedHeight(manualHeight: 250, textHeight: 10, shape: .circle, padding: 8, visibleScreenHeight: 1200)
        XCTAssertEqual(shrunk.height, 250)
    }

    // MARK: Safe text areas

    func testSafeTextRectCornersAreInsideEveryShape() {
        let sizes = [CGSize(width: 220, height: 220), CGSize(width: 300, height: 180), CGSize(width: 160, height: 520)]
        for shape in NoteShape.allCases {
            for size in sizes {
                let rect = CGRect(origin: .zero, size: size)
                let path = shape.path(in: rect)
                let safe = shape.safeTextRect(in: rect)
                let probes = [CGPoint(x: safe.minX, y: safe.minY), CGPoint(x: safe.maxX, y: safe.minY),
                              CGPoint(x: safe.minX, y: safe.maxY), CGPoint(x: safe.maxX, y: safe.maxY),
                              CGPoint(x: safe.midX, y: safe.minY), CGPoint(x: safe.midX, y: safe.maxY),
                              CGPoint(x: safe.minX, y: safe.midY), CGPoint(x: safe.maxX, y: safe.midY)]
                for p in probes {
                    XCTAssertTrue(path.contains(p), "\(shape) \(size): \(p) is outside the shape")
                }
            }
        }
    }

    func testShapesFillTheirRect() {
        for shape in NoteShape.allCases {
            let rect = CGRect(x: 10, y: 20, width: 200, height: 100)
            let box = shape.path(in: rect).boundingBoxOfPath
            XCTAssertEqual(box.minX, rect.minX, accuracy: 1.5, "\(shape)")
            XCTAssertEqual(box.maxX, rect.maxX, accuracy: 1.5, "\(shape)")
            XCTAssertEqual(box.minY, rect.minY, accuracy: 3, "\(shape)")
            XCTAssertEqual(box.maxY, rect.maxY, accuracy: 3, "\(shape)")
        }
    }

    // MARK: Colors

    func testAutomaticTextColorMeetsContrastForEveryColor() {
        for color in NoteColor.allCases {
            let ratio = NoteRGB.contrastRatio(color.rgb, color.automaticTextColor)
            XCTAssertGreaterThanOrEqual(ratio, 4.5, "\(color) text contrast \(ratio)")
        }
    }

    func testEightColorsAndSixShapes() {
        XCTAssertEqual(NoteColor.allCases.count, 8)
        XCTAssertEqual(NoteShape.allCases.count, 6)
    }
}
