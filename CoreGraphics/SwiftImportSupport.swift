// Swift wrappers over the public C interfaces declared in CoreGraphics headers.
// The compiler owns the Swift ABI metadata, enum descriptors and conformances.
@_exported import CoreGraphics
@_exported import CoreFoundation

public enum CGPathFillRule {
    case winding
    case evenOdd
}

extension CGContext {
    public func fillPath(using rule: CGPathFillRule = .winding) {
        switch rule {
        case .winding: CGContextFillPath(self)
        case .evenOdd: CGContextEOFillPath(self)
        }
    }
    public func showGlyphs(_ glyphs: [UInt16], at positions: [CGPoint]) {
        precondition(glyphs.count == positions.count, "Each glyph needs a position")
        guard !glyphs.isEmpty else { return }
        glyphs.withUnsafeBufferPointer { glyphBuffer in
            positions.withUnsafeBufferPointer { positionBuffer in
                CGContextShowGlyphsAtPositions(self, glyphBuffer.baseAddress!,
                    positionBuffer.baseAddress!, glyphs.count)
            }
        }
    }
}

extension CGMutablePath {
    public func move(to point: CGPoint, transform: CGAffineTransform = CGAffineTransformIdentity) {
        var t = transform
        CGPathMoveToPoint(self, &t, point.x, point.y)
    }
    public func addLine(to point: CGPoint, transform: CGAffineTransform = CGAffineTransformIdentity) {
        var t = transform
        CGPathAddLineToPoint(self, &t, point.x, point.y)
    }
    public func addCurve(to end: CGPoint, control1: CGPoint, control2: CGPoint,
                         transform: CGAffineTransform = CGAffineTransformIdentity) {
        var t = transform
        CGPathAddCurveToPoint(self, &t, control1.x, control1.y, control2.x, control2.y, end.x, end.y)
    }
    public func addArc(center: CGPoint, radius: CGFloat, startAngle: CGFloat,
                       endAngle: CGFloat, clockwise: Bool,
                       transform: CGAffineTransform = CGAffineTransformIdentity) {
        var t = transform
        CGPathAddArc(self, &t, center.x, center.y, radius, startAngle, endAngle, clockwise)
    }
    public func addPath(_ path: CGPath, transform: CGAffineTransform = CGAffineTransformIdentity) {
        var t = transform
        CGPathAddPath(self, &t, path)
    }
    public func addLines(between points: [CGPoint], transform: CGAffineTransform = CGAffineTransformIdentity) {
        guard !points.isEmpty else { return }
        var t = transform
        points.withUnsafeBufferPointer { buffer in
            CGPathAddLines(self, &t, buffer.baseAddress!, buffer.count)
        }
    }
}

extension CGPath {
    public func copy(strokingWithWidth width: CGFloat, lineCap: CGLineCap,
                     lineJoin: CGLineJoin, miterLimit: CGFloat,
                     transform: CGAffineTransform = CGAffineTransformIdentity) -> CGPath {
        var t = transform
        guard let copy = CGPathCreateCopyByStrokingPath(self, &t, width, lineCap, lineJoin, miterLimit) else {
            preconditionFailure("Unable to create stroked path")
        }
        return copy
    }
}

extension CGRect {
    public var width: CGFloat { return abs(size.width) }
    public var height: CGFloat { return abs(size.height) }
}

extension CGRect: Equatable {
    public static func == (lhs: CGRect, rhs: CGRect) -> Bool {
        if CGRectIsNull(lhs) && CGRectIsNull(rhs) { return true }
        return CGRectEqualToRect(CGRectStandardize(lhs), CGRectStandardize(rhs))
    }
}
extension CGRect: Hashable {
    public func hash(into hasher: inout Hasher) {
        if CGRectIsNull(self) {
            hasher.combine(0 as UInt8)
            return
        }
        let rect = CGRectStandardize(self)
        hasher.combine(1 as UInt8)
        hasher.combine(rect.origin.x)
        hasher.combine(rect.origin.y)
        hasher.combine(rect.size.width)
        hasher.combine(rect.size.height)
    }
}
