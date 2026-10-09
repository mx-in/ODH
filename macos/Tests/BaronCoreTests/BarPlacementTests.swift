import CoreGraphics
import Testing
@testable import BaronCore

struct BarPlacementTests {
    private let screen = CGRect(x: 0, y: 25, width: 1000, height: 700)
    private let bar = CGSize(width: 200, height: 30)

    @Test func sitsAboveTheSelectionCentredOnThePointer() {
        let selection = CGRect(x: 300, y: 400, width: 200, height: 16)
        let frame = BarPlacement.frame(barSize: bar, selection: selection, pointer: CGPoint(x: 420, y: 410), visibleFrame: screen)
        #expect(frame.maxY == selection.minY - BarPlacement.gap)
        #expect(frame.midX == 420)
    }

    @Test func pointerOutsideTheSelectionIsClampedToIt() {
        let selection = CGRect(x: 300, y: 400, width: 100, height: 16)
        let frame = BarPlacement.frame(barSize: bar, selection: selection, pointer: CGPoint(x: 900, y: 410), visibleFrame: screen)
        #expect(frame.midX == 400)
    }

    @Test func goesBelowWhenThereIsNoRoomAbove() {
        let selection = CGRect(x: 300, y: 40, width: 100, height: 16)
        let frame = BarPlacement.frame(barSize: bar, selection: selection, pointer: CGPoint(x: 350, y: 48), visibleFrame: screen)
        #expect(frame.minY == selection.maxY + BarPlacement.gap)
    }

    @Test func staysOnScreenAtTheEdges() {
        let selection = CGRect(x: 0, y: 400, width: 20, height: 16)
        let frame = BarPlacement.frame(barSize: bar, selection: selection, pointer: CGPoint(x: 5, y: 405), visibleFrame: screen)
        #expect(frame.minX == screen.minX)
        let right = BarPlacement.frame(barSize: bar, selection: CGRect(x: 980, y: 400, width: 20, height: 16), pointer: CGPoint(x: 995, y: 405), visibleFrame: screen)
        #expect(right.maxX == screen.maxX)
    }

    @Test func usesThePointerWithoutBounds() {
        let pointer = CGPoint(x: 500, y: 300)
        let frame = BarPlacement.frame(barSize: bar, selection: nil, pointer: pointer, visibleFrame: screen)
        #expect(frame.midX == 500)
        #expect(frame.maxY == pointer.y - BarPlacement.pointerOffset)
    }

    @Test func emptyBoundsCountAsUnknown() {
        let pointer = CGPoint(x: 500, y: 300)
        let frame = BarPlacement.frame(barSize: bar, selection: .zero, pointer: pointer, visibleFrame: screen)
        #expect(frame.midX == 500)
    }
}
