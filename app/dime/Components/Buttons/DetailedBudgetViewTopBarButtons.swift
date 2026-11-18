//
//  DetailedBudgetViewTopBarButtons.swift
//  dime
//
//  Created by Rafael Soh on 4/11/23.
//

import Foundation
import SwiftUI

struct DetailedBudgetViewTopBarButton: View {
    var imageName: String
    var color: Color
    var action: () -> Void

    var body: some View {
        Button(action: {
            self.action()
        }) {
            Image(systemName: imageName)
                .font(.system(.callout, design: .rounded).weight(.semibold))
                .foregroundColor(color)
                .padding(8)
//                .frame(width: 30, height: 30)
                .dimeGlass(in: Circle(), interactive: true, tint: color.opacity(0.3), fallback: color.opacity(0.23))
                .contentShape(Circle())
        }
    }
}
