//
//  ChartView.swift
//  ScheduleChart
//
//  Created by Alexander Graschenkov on 10/03/2019.
//  Copyright © 2019 Alex the Best. All rights reserved.
//

import UIKit

class ChartView: UIView {
    struct Range {
        var from: Float
        var to: Float
    }
    
    struct RangeI {
        var from: Int64
        var to: Int64
    }
    
    var drawGrid: Bool = true
    var showZeroYValue: Bool = true
    var drawOutsideChart: Bool = false
    var lineWidth: CGFloat = 2.0
    lazy var verticalAxe: VerticalAxe = VerticalAxe(view: self)
    lazy var horisontalAxe: HorisontalAxe = HorisontalAxe(view: self)
    let labelsPool: LabelsPool = LabelsPool()
    
    var data: [ChartData] = [] {
        didSet {
            dataMinTime = -1
            dataMaxTime = -1
            for d in data {
                if dataMinTime < 0 {
                    dataMinTime = d.items.first!.time
                    dataMaxTime = d.items.last!.time
                    continue
                }
                dataMinTime = min(dataMinTime, d.items.first!.time)
                dataMaxTime = max(dataMaxTime, d.items.last!.time)
            }
            displayRange = RangeI(from: dataMinTime, to: dataMaxTime)
            
            
            var maxVal: Float = 0
            for d in data {
                for item in d.items {
                    maxVal = max(item.value, maxVal)
                }
            }
            maxVal = ceil(maxVal / 100) * 100
            setMaxVal(val: maxVal, animationDuration: 0)
            setNeedsDisplay()
        }
    }
    var dataAlpha: [Float] = []
    private(set) var dataMinTime: Int64 = -1
    private(set) var dataMaxTime: Int64 = -1
    var displayRange: RangeI = RangeI(from: 0, to: 0)
    var displayVerticalRange: Range = Range(from: 0, to: 200)
    var onDrawDebug: (()->())?
    var maxValAnimatorCancel: Cancelable?
    var rangeAnimatorCancel: Cancelable?
    var chartInset = UIEdgeInsets(top: 0, left: 40, bottom: 30, right: 30)
    
    func setMaxVal(val: Float, animationDuration: Double) {
        maxValAnimatorCancel?()
        if animationDuration > 0 {
            let fromVal = displayVerticalRange.to
            maxValAnimatorCancel = DisplayLinkAnimator.animate(duration: animationDuration) { (percent) in
                self.displayVerticalRange.to = (val - fromVal) * Float(percent) + fromVal
                self.setNeedsDisplay()
            }
        } else {
            displayVerticalRange.to = val
            self.setNeedsDisplay()
        }
        
        if drawGrid {
            verticalAxe.setMaxVal(val, animationDuration: animationDuration)
        }
    }
    
    func setRange(minTime: Int64, maxTime: Int64, animated: Bool) {
        rangeAnimatorCancel?()
        if !animated {
            displayRange.from = minTime
            displayRange.to = maxTime
            setNeedsDisplay()
            horisontalAxe.setRange(minTime: displayRange.from, maxTime: displayRange.to, animationDuration: 0.2)
            // TODO
            return
        }
        
        let fromRange = displayRange
        rangeAnimatorCancel = DisplayLinkAnimator.animate(duration: 0.5, closure: { (percent) in
            self.displayRange.from = Int64(CGFloat(minTime - fromRange.from) * percent) + fromRange.from
            self.displayRange.to = Int64(CGFloat(maxTime - fromRange.to) * percent) + fromRange.to
            self.setNeedsDisplay()
            if percent == 1 {
                self.rangeAnimatorCancel = nil
            }
        })
        
        horisontalAxe.setRange(minTime: minTime, maxTime: maxTime, animationDuration: 0.5)
    }
    
    override func draw(_ rect: CGRect) {
        super.draw(rect)
       
        guard let ctx = UIGraphicsGetCurrentContext() else {
            return
        }
        
        onDrawDebug?()
        if drawGrid {
            if verticalAxe.maxVal == nil {
                verticalAxe.setMaxVal(displayVerticalRange.to)
            }
            verticalAxe.drawGrid(ctx: ctx, inset: chartInset)
            if horisontalAxe.maxTime == 0 && data.count > 0 {
                horisontalAxe.setRange(minTime: displayRange.from, maxTime: displayRange.to)
            }
            if rangeAnimatorCancel != nil {
                horisontalAxe.layoutLabels()
            }
        }
        
        ctx.setLineWidth(lineWidth)
        ctx.setLineJoin(.round)
        var chartRect = bounds.inset(by: chartInset)
        
        var fromTime = displayRange.from
        var toTime = displayRange.to
        if drawOutsideChart {
            (chartRect, fromTime, toTime) = expandDrawRange(rect: chartRect,
                                                            inset: chartInset,
                                                            from: fromTime,
                                                            to: toTime)
        } else {
            ctx.clip(to: chartRect)
        }
        
        for (_, d) in data.enumerated() {
//            if d.alpha == 0 { continue }
            drawData(d, alpha: 1.0, ctx: ctx, from: fromTime, to: toTime, inRect: chartRect)
        }
        
        if !drawOutsideChart {
            ctx.resetClip()
        }
    }
    
 
    func drawData(_ data: ChartData, alpha: CGFloat, ctx: CGContext, from: Int64, to: Int64, inRect rect: CGRect) {
        guard let drawFrom = data.floorIndex(time: from),
            let drawTo = data.ceilIndex(time: to) else {
            return
        }
        let color = data.color.withAlphaComponent(alpha).cgColor
        let firstItem = data.items[drawFrom]
        let firstPoint = convertPos(time: firstItem.time, val: firstItem.value, inRect: rect, fromTime: from, toTime: to)
        
        if drawFrom == drawTo {
            let circle = CGRect(x: firstPoint.x-lineWidth/2.0,
                                y: firstPoint.y-lineWidth/2.0,
                                width: lineWidth,
                                height: lineWidth)
            ctx.setFillColor(color)
            ctx.fillEllipse(in: circle)
            return
        }
        
        ctx.move(to: firstPoint)
        for i in (drawFrom+1)...drawTo {
            let item = data.items[i]
            
            let p = convertPos(time: item.time, val: item.value, inRect: rect, fromTime: from, toTime: to)
            ctx.addLine(to: p)
        }
        ctx.setStrokeColor(color)
        ctx.strokePath()
    }
    
    private func convertPos(time: Int64, val: Float, inRect rect: CGRect, fromTime: Int64, toTime: Int64) -> CGPoint {
        let xPercent = Float(time - fromTime) / Float(toTime - fromTime)
        let x = rect.origin.x + rect.width * CGFloat(xPercent)
        let yPercent = (val - displayVerticalRange.from) / (displayVerticalRange.to - displayVerticalRange.from)
        let y = rect.maxY - rect.height * CGFloat(yPercent)
        return CGPoint(x: x, y: y)
    }
}

private extension ChartView { // Data draw helpers
    func expandDrawRange(rect: CGRect, inset: UIEdgeInsets, from: Int64, to: Int64) -> (CGRect, Int64, Int64) {
        let leftRectPercent = inset.left / rect.width
        let leftTimePercent = CGFloat(dataMinTime - from) / CGFloat(from - to)
        let leftPercent = min(leftRectPercent, leftTimePercent)
        
        let rightRectPercent = inset.right / rect.width
        let rightTimePercent = CGFloat(dataMaxTime - to) / CGFloat(to - from)
        let rightPercent = min(rightRectPercent, rightTimePercent)
        
        let drawRect = rect.inset(by: UIEdgeInsets(top: 0,
                                                   left: -leftPercent * rect.width,
                                                   bottom: 0,
                                                   right: -rightPercent * rect.width))
        let drawFrom = from + Int64(CGFloat(from - to) * leftPercent)
        let drawTo = to + Int64(CGFloat(to - from) * rightPercent)
        
        return (drawRect, drawFrom, drawTo)
    }
}
