import CoreGraphics
import Darwin

var failures = 0
func check(_ condition: Bool, _ label: String) {
    if !condition { print("FAIL \(label)"); failures += 1 }
}

// Set uses the generated Hashable witness table; == alone does not exercise it.
let reversed = CGRectMake(10, 20, -3, -4)
let standard = CGRectMake(7, 16, 3, 4)
check(reversed == standard, "CGRect standardized equality")
check(Set([reversed, standard]).count == 1, "CGRect Hashable witness")
check(Set([CGRectNull, CGRectNull]).count == 1, "CGRect null hashing")
check(reversed.width == 3 && reversed.height == 4, "CGRect width/height getters")
check(standard.width == 3 && standard.height == 4, "CGRect positive dimensions")
check(CGRectZero.width == 0 && CGRectZero.height == 0, "CGRect zero dimensions")
check(CGRectEqualToRect(CGRectStandardize(reversed), standard), "C standardized equality from Swift")
func equal<T: Equatable>(_ lhs: T, _ rhs: T) -> Bool { return lhs == rhs }
check(equal(reversed, standard), "CGRect generic Equatable witness")
check(reversed.hashValue == standard.hashValue, "CGRect equal hash values")
check(Set([reversed, standard, CGRectMake(8, 16, 3, 4)]).count == 2,
    "CGRect hashing distinguishes different rectangles")

let path = CGMutablePath()
let transform = CGAffineTransform(a: 2, b: 0, c: 0, d: 3, tx: 5, ty: 7)
path.move(to: CGPoint(x: 1, y: 2), transform: transform)
path.addLine(to: CGPoint(x: 4, y: 5), transform: transform)
var point = CGPathGetCurrentPoint(path)
check(point.x == 13 && point.y == 22, "transformed move/line")
path.addCurve(to: CGPoint(x: 8, y: 9), control1: CGPoint(x: 4, y: 5),
    control2: CGPoint(x: 6, y: 7), transform: transform)
point = CGPathGetCurrentPoint(path)
check(point.x == 21 && point.y == 34, "transformed curve")
let lines = CGMutablePath()
lines.addLines(between: [CGPoint(x: 0, y: 0), CGPoint(x: 2, y: 3)], transform: transform)
point = CGPathGetCurrentPoint(lines)
check(point.x == 9 && point.y == 16, "transformed array of points")
let copy = CGMutablePath()
copy.addPath(lines, transform: transform)
point = CGPathGetCurrentPoint(copy)
check(point.x == 23 && point.y == 55, "transformed addPath")
let arc = CGMutablePath()
arc.addArc(center: CGPoint(x: 0, y: 0), radius: 2, startAngle: 0,
    endAngle: .pi / 2, clockwise: false, transform: transform)
point = CGPathGetCurrentPoint(arc)
check(abs(point.x - 5) < 0.00001 && abs(point.y - 13) < 0.00001, "transformed arc")

func fill(_ rule: CGPathFillRule) -> Int {
    var pixels = [UInt8](repeating: 0, count: 16 * 16 * 4)
    return pixels.withUnsafeMutableBytes { buffer in
        let space = CGColorSpaceCreateDeviceRGB()!
        guard let rawContext = CGBitmapContextCreate(buffer.baseAddress, 16, 16, 8, 64,
            space, CGBitmapInfo(UInt32(kCGBitmapByteOrder32Big) | CGImageAlphaInfo.premultipliedLast.rawValue)) else {
            check(false, "bitmap context creation")
            return -1
        }
        let context = rawContext.takeRetainedValue()
        CGContextSetRGBFillColor(context, 1, 0, 0, 1)
        CGContextAddRect(context, CGRectMake(0, 0, 16, 16))
        CGContextAddRect(context, CGRectMake(4, 4, 8, 8))
        context.fillPath(using: rule)
        return Int(buffer[4 * (8 * 16 + 8) + 3])
    }
}
check(fill(.winding) == 255, "Swift winding enum invocation and pixels")
check(fill(.evenOdd) == 0, "Swift evenOdd enum invocation and pixels")
print("RESULT swift-client failures=\(failures)")
exit(failures == 0 ? 0 : 1)
