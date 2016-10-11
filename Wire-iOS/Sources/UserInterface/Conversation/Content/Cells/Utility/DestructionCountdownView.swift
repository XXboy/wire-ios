//
// Wire
// Copyright (C) 2016 Wire Swiss GmbH
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program. If not, see http://www.gnu.org/licenses/.
//


import Foundation
import Cartography


public final class DestructionCountdownView: UIView {

    public let numberOfDots = 5
    private let padding: CGFloat = 1
    private let dotSize: CGFloat = 3
    private var dots = [UIView]()
    private let fullColor = UIColor(for: .brightOrange)
    private let emptyColor = UIColor(for: .brightOrange).withAlphaComponent(0.5)

    private var fullDots: Int = 0 {
        didSet(oldValue) {
            guard oldValue != fullDots else { return }
            dots.dropLast(fullDots).forEach {
                $0.backgroundColor = emptyColor
            }
        }
    }

    public init() {
        super.init(frame: .zero)
        setupViews()
        createConstraints()
    }
    
    required public init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func update(fraction: CGFloat) {
        fullDots = Int(CGFloat(numberOfDots) * fraction.clamp(0, upper: 1))
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        createConstraints()
        roundDots()
    }

    private func roundDots() {
        dots.forEach {
            $0.layer.cornerRadius = bounds.width / 2
        }
    }

    private func setupViews() {
        dots = (0..<numberOfDots).map { _ in UIView() }
        dots.forEach {
            addSubview($0)
            $0.backgroundColor = fullColor
        }
        roundDots()
    }

    private func createConstraints() {
        dots.forEach { dot in
            constrain(dot, self) { dot, view in
                dot.left == view.left
                dot.right == view.right
                dot.height == dotSize
            }
        }
        constrain(self, dots.first!, dots.last!) { view, first, last in
            first.top == view.top
            last.bottom == view.bottom
            view.width == dotSize
        }
        zip(dots.dropLast(), dots.dropFirst()).forEach { top, bottom in
            constrain(top, bottom) { top, bottom in
                bottom.top == top.bottom + padding
            }
        }
    }
}
