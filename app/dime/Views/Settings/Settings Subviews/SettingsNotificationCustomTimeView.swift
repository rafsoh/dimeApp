//
//  SettingsNotificationCustomTimeView.swift
//  dime
//
//  Created by Ahmer Mughal on 31.07.25.
//

import SwiftUI

struct SettingsNotificationCustomTimeView: View {
    @Environment(\.presentationMode) var presentationMode: Binding<PresentationMode>

    @Binding var customTimerList: [Date]
    
    var onDismiss: (() -> Void)
    
    var body: some View {
        VStack {
            Text("Notifications")
              .font(.system(.title3, design: .rounded).weight(.semibold))
              .foregroundColor(Color.PrimaryText)
              .frame(maxWidth: .infinity)
              .overlay(alignment: .leading) {
                Button {
                  self.presentationMode.wrappedValue.dismiss()
                    self.onDismiss()
                } label: {
                  SettingsBackButton()
                }
              }
              .padding(.bottom, 20)
              .padding(.horizontal, 20)
            
            if #available(iOS 16.0, *) {
                List {
                     ForEach(customTimerList.indices, id: \.self) { index in
                         HStack{
                             Text("Custom Time")
                               .font(.system(.body, design: .rounded))
                               .foregroundColor(Color.PrimaryText)

                             Spacer()
                             
                             DatePicker(
                                 "Select Time",
                                 selection: Binding(
                                     get: { customTimerList[index] },
                                     set: { customTimerList[index] = $0 }
                                 ),
                                 displayedComponents: .hourAndMinute
                             )
                             .labelsHidden()
                         }
                         .listRowBackground(Color.SettingsBackground)
                         .padding(.vertical, 1)
                         
                     }
                     .onDelete(perform: delete)
                     
                     Button(action: {
                         customTimerList.append(Date()) // Add new date picker
                     }) {
                         HStack {
                             Image(systemName: "plus.circle.fill")
                                 .font(.title2)
                                 .foregroundColor(Color.PrimaryText)
                             Text("Add Time")
                                 .font(.system(.body, design: .rounded))
                                 .foregroundColor(Color.PrimaryText)
                         }
                         .foregroundColor(.blue)
                         .frame(maxWidth: .infinity, alignment: .center)
                         .padding(.vertical, 4)
                     }
                     .listRowBackground(Color.SettingsBackground)

                 }
                .scrollContentBackground(.hidden)
                
            } else {
                List {
                     ForEach(customTimerList.indices, id: \.self) { index in
                         HStack{
                             Text("Custom Time")
                               .font(.system(.body, design: .rounded))
                               .foregroundColor(Color.PrimaryText)

                             Spacer()
                             
                             DatePicker(
                                 "Select Time",
                                 selection: Binding(
                                     get: { customTimerList[index] },
                                     set: { customTimerList[index] = $0 }
                                 ),
                                 displayedComponents: .hourAndMinute
                             )
                             .labelsHidden()
                         }
                         .listRowBackground(Color.SettingsBackground)
                         .padding(.vertical, 1)
                         
                     }
                     
                     Button(action: {
                         customTimerList.append(Date())
                     }) {
                         HStack {
                             Image(systemName: "plus.circle.fill")
                                 .font(.title2)
                                 .foregroundColor(Color.PrimaryText)
                             Text("Add Time")
                                 .font(.system(.body, design: .rounded))
                                 .foregroundColor(Color.PrimaryText)
                         }
                         .foregroundColor(.blue)
                         .frame(maxWidth: .infinity, alignment: .center)
                         .padding(.vertical, 9)
                         .padding(.horizontal, 0)
                     }
                     .listRowBackground(Color.SettingsBackground)
                 }
                .background(Color.clear)
            }
            
        }
        .navigationBarBackButtonHidden(true)
        .navigationBarTitle("")
        .navigationBarHidden(true)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.PrimaryBackground)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .padding(.vertical, 20)
    }
    
    func delete(at offsets: IndexSet) {
        customTimerList.remove(atOffsets: offsets)
    }
}

#Preview {
    SettingsNotificationCustomTimeView(customTimerList: .constant([Date.now, Date.now]), onDismiss: {})
}
