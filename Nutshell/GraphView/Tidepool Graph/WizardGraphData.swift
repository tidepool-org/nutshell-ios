/*
* Copyright (c) 2015, Tidepool Project
*
* This program is free software; you can redistribute it and/or modify it under
* the terms of the associated License, which is identical to the BSD 2-Clause
* License as published by the Open Source Initiative at opensource.org.
*
* This program is distributed in the hope that it will be useful, but WITHOUT
* ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
* FOR A PARTICULAR PURPOSE. See the License for more details.
*
* You should have received a copy of the License along with this program; if
* not, you can obtain one from Tidepool Project at tidepool.org.
*/

import UIKit
// FIXME: comparison operators with optionals were removed from the Swift Standard Libary.
// Consider refactoring the code to use the non-optional operators.
fileprivate func < <T : Comparable>(lhs: T?, rhs: T?) -> Bool {
  switch (lhs, rhs) {
  case let (l?, r?):
    return l < r
  case (nil, _?):
    return true
  default:
    return false
  }
}

// FIXME: comparison operators with optionals were removed from the Swift Standard Libary.
// Consider refactoring the code to use the non-optional operators.
fileprivate func > <T : Comparable>(lhs: T?, rhs: T?) -> Bool {
  switch (lhs, rhs) {
  case let (l?, r?):
    return l > r
  default:
    return rhs < lhs
  }
}



class WizardGraphDataType: GraphDataType {

    var bolusId: String?
    var recommendedNet: NSNumber?
    var bolusTopY: CGFloat?
    
    init(value: CGFloat, timeOffset: TimeInterval, bolusId: String?, recommendedNet: NSNumber?) {
        super.init(value: value, timeOffset: timeOffset)
        self.bolusId = bolusId
        self.recommendedNet = recommendedNet
    }
    
    override func typeString() -> String {
        return "wizard"
    }

}

class WizardGraphDataLayer: TidepoolGraphDataLayer {
    
    // vars for drawing datapoints of this type
    var pixelsPerValue: CGFloat = 0.0
    let circleRadius: CGFloat = 9.0
    var lastCircleDrawn = CGRect.null
    var context: CGContext?
    
    // Bolus drawing will store rects here. E.g., Wizard circles are drawn just over associated Bolus labels.
    var bolusRects: [CGRect] = []
    
    fileprivate let kWizardCircleDiameter: CGFloat = 31.0

    //
    // MARK: - Loading data
    //

    override func nominalPixelWidth() -> CGFloat {
        return kWizardCircleDiameter
    }
    
    override func typeString() -> String {
        return "wizard"
    }
    
    override func loadEvent(_ event: CommonData, timeOffset: TimeInterval) {
        if let event = event as? Wizard {
            let value = event.carbInput ?? 0.0
            let floatValue = round(CGFloat(value))
            dataArray.append(WizardGraphDataType(value: floatValue, timeOffset: timeOffset, bolusId: event.bolus, recommendedNet: event.recommendedNet))
            
            // Let recommended bolus values figure into the bolus value scaling as well!
            if let recommended = event.recommendedNet {
                let recommendedValue = CGFloat(recommended)
                if recommendedValue > layout.maxBolus {
                    layout.maxBolus = recommendedValue
                }
            }

        }
    }

    //
    // MARK: - Drawing data points
    //

    // override for any draw setup
    override func configureForDrawing() {
        self.pixelsPerValue = layout.yPixelsGlucose/layout.kGlucoseRange
        context = UIGraphicsGetCurrentContext()
   }
    
    // override!
    override func drawDataPointAtXOffset(_ xOffset: CGFloat, dataPoint: GraphDataType) {
        
        if dataPoint.value == 0.0 {
            // Don't plot nil or zero values - probably used for recommended bolus record!
            //NSLog("Skip plot of wizard with zero value!")
            return
        }
        
        if let wizard = dataPoint as? WizardGraphDataType {
            let centerX = xOffset
            let circleDiameter = kWizardCircleDiameter
            let value = round(dataPoint.value)
            // Carb circle should be centered at timeline
            let offsetX = centerX - (circleDiameter/2)
            var wizardRect = CGRect(x: offsetX, y: layout.yBottomOfWizard - circleDiameter, width: circleDiameter, height: circleDiameter)
            var yAtBolusTop = bolusYAtPosition(wizardRect)
            if wizard.bolusTopY != nil {
                yAtBolusTop = wizard.bolusTopY
            }
            if let yAtBolusTop = yAtBolusTop {
                wizardRect.origin.y = yAtBolusTop - circleDiameter
            }
            let wizardOval = UIBezierPath(ovalIn: wizardRect)
            Styles.goldColor.setFill()
            wizardOval.fill()
            // Draw background colored border to separate the circle from other objects
            layout.backgroundColor.setStroke()
            wizardOval.lineWidth = 0.5
            wizardOval.stroke()
            
            // Label Drawing
            let labelRect = wizardRect
            let labelText = String(Int(value))
            let labelStyle = NSParagraphStyle.default.mutableCopy() as! NSMutableParagraphStyle
            labelStyle.alignment = .center
            
            let labelAttrStr = NSMutableAttributedString(string: labelText, attributes: [NSFontAttributeName: Styles.smallSemiboldFont, NSForegroundColorAttributeName: Styles.darkPurpleColor, NSParagraphStyleAttributeName: labelStyle])
            
            let labelTextHeight: CGFloat = ceil(labelAttrStr.boundingRect(with: CGSize(width: labelRect.width, height: CGFloat.infinity), options: NSStringDrawingOptions.usesLineFragmentOrigin, context: nil).size.height)
            
            context!.saveGState()
            context!.clip(to: labelRect);
            labelAttrStr.draw(in: CGRect(x: labelRect.minX, y: labelRect.minY + (labelRect.height - labelTextHeight) / 2, width: labelRect.width, height: labelTextHeight))
            context!.restoreGState()
        }
    }
    
    //
    // MARK: - Tidepool specific utility functions
    //
    
    func bolusYAtPosition(_ rect: CGRect) -> CGFloat? {
        var result: CGFloat?
        let rectLeft = rect.origin.x
        let rectRight = rectLeft + rect.width
        for bolusRect in bolusRects {
            let bolusLeftX = bolusRect.origin.x
            let bolusRightX = bolusLeftX + bolusRect.width
            if bolusRightX > rectLeft && bolusLeftX < rectRight {
                if bolusRect.height > result {
                    // return the bolusRect that is largest and intersects the x position of the target rect
                    result = bolusRect.height
                }
            }
        }
        return result
    }

}
