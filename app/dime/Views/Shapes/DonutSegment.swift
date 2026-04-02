//
//  DonutSegment.swift
//  dime
//

import Foundation
import SwiftUI

struct DonutSegment: Shape {
    var startAngle: Double
    var endAngle: Double
    var thickness: CGFloat

    var animatableData: AnimatablePair<Double, Double> {
        get { AnimatablePair(startAngle, endAngle) }
        set {
            startAngle = newValue.first
            endAngle = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let outerRadius = min(rect.width, rect.height) / 2
        let innerRadius = outerRadius - thickness

        var path = Path()
        path.addArc(
            center: center, radius: outerRadius,
            startAngle: .degrees(startAngle - 90),
            endAngle: .degrees(endAngle - 90),
            clockwise: false)
        path.addArc(
            center: center, radius: innerRadius,
            startAngle: .degrees(endAngle - 90),
            endAngle: .degrees(startAngle - 90),
            clockwise: true)
        path.closeSubpath()
        return path
    }
}
