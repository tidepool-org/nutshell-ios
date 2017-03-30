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


@IBDesignable class ScaledSwitch: UISwitch {
    
    @IBInspectable var scale : CGFloat = 1 {
        didSet {
            setup()
        }
    }
    
//    //from storyboard
//    required init?(coder aDecoder: NSCoder) {
//        super.init(coder: aDecoder)
//        setup()
//    }
//    
//    //from code
//    override init(frame: CGRect) {
//        super.init(frame: frame)
//        setup()
//    }
    
    private func setup(){
        self.transform = CGAffineTransform(scaleX: scale, y: scale)
    }
    
//    override func prepareForInterfaceBuilder() {
//        setup()
//        super.prepareForInterfaceBuilder()
//    }
    
    
}
