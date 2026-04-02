//
//  CustomTabBar.swift
//  xpenz
//
//  Created by Rafael Soh on 20/5/22.
//

import Foundation
import SwiftUI

struct CustomTabBar: View {
    @EnvironmentObject var appLockVM: AppLockViewModel
    @Binding var currentTab: String
    var topEdge: CGFloat
    var bottomEdge: CGFloat
    @State var addTransaction: Bool = false

    @State var checkingFace: Bool = false

    @FetchRequest(sortDescriptors: []) private var transactions: FetchedResults<Transaction>
    @FetchRequest(sortDescriptors: []) private var categories: FetchedResults<Category>

    @State var count = 0
    @Binding var counter: Int

    var launchAdd: Bool

    @AppStorage("confetti", store: UserDefaults(suiteName: "group.com.vanxun.dime")) var confetti: Bool = false
    @AppStorage("firstTransactionViewLaunch", store: UserDefaults(suiteName: "group.com.vanxun.dime")) var firstLaunch: Bool = true

    @State var animate = false

    // Voice input
    @StateObject private var speechRecognizer = SpeechRecognizer()
    @State private var isProcessingVoice = false
    @State private var voiceResults: [ReceiptScanResult]? = nil
    @State private var longPressTriggeredAt: Date? = nil

    private var isZoomed: Bool {
        UIScreen.main.scale != UIScreen.main.nativeScale
    }

    var body: some View {
        HStack(spacing: 4) {
            TabButton(image: "Log", zoomed: isZoomed, currentTab: $currentTab)

            TabButton(image: "Insights", zoomed: isZoomed, currentTab: $currentTab)

            ZStack {
                RoundedRectangle(cornerRadius: 28, style: .continuous).fill(Color.DarkBackground.opacity(0.6))
                    .frame(width: 95, height: 68)
                    .opacity(self.animate ? 0 : 1)
                    .scaleEffect(self.animate ? 1 : 0.4)

                RoundedRectangle(cornerRadius: 20.5, style: .continuous).fill(Color.DarkBackground.opacity(0.8))
                    .frame(width: 80, height: 53)
                    .opacity(self.animate ? 0 : 1)
                    .scaleEffect(self.animate ? 1 : 0.6)

                Image(systemName: speechRecognizer.isRecording ? "mic.fill" : "plus")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(speechRecognizer.isRecording ? .white : Color.LightIcon)
                    .frame(width: 65, height: 38)
                    .background(
                        speechRecognizer.isRecording ? Color.red : (isProcessingVoice ? Color.IncomeGreen : Color.DarkBackground),
                        in: RoundedRectangle(cornerRadius: 13, style: .continuous)
                    )
                    .scaleEffect(speechRecognizer.isRecording ? 1.1 : 1.0)
                    .animation(
                        speechRecognizer.isRecording ?
                            .easeInOut(duration: 0.8).repeatForever(autoreverses: true) : .default,
                        value: speechRecognizer.isRecording
                    )
                    .padding(15)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        // Debounce: ignore tap within 1s of long press trigger
                        if let t = longPressTriggeredAt, Date().timeIntervalSince(t) < 1.0 {
                            return
                        }
                        if speechRecognizer.isRecording {
                            speechRecognizer.stopRecording()
                        } else if !isProcessingVoice {
                            let impactMed = UIImpactFeedbackGenerator(style: .light)
                            impactMed.impactOccurred()
                            addTransaction = true
                        }
                    }
                    .onLongPressGesture(minimumDuration: 0.5) {
                        startVoiceRecording()
                    }
            }
            .onAppear {
                if transactions.isEmpty {
                    withAnimation(.easeInOut(duration: 1.9).repeatForever(autoreverses: false)) {
                        self.animate.toggle()
                    }
                }
            }
            .accessibilityLabel(speechRecognizer.isRecording ? "Stop voice input" : "Add New Transaction")

            TabButton(image: "Budget", zoomed: isZoomed, currentTab: $currentTab)

            TabButton(image: "Settings", zoomed: isZoomed, currentTab: $currentTab)
        }
        .padding(.horizontal, 15)
        .padding(.bottom, bottomEdge - 10)
        .frame(maxWidth: .infinity)
        .background(Color.PrimaryBackground)
        .overlay(alignment: .top) {
            if speechRecognizer.isRecording {
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 8, height: 8)
                        .opacity(speechRecognizer.isRecording ? 1.0 : 0.3)
                        .animation(
                            .easeInOut(duration: 0.6).repeatForever(autoreverses: true),
                            value: speechRecognizer.isRecording
                        )
                    Text("Recording...")
                        .font(.system(.caption, design: .rounded).weight(.semibold))
                        .foregroundColor(.red)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.ultraThinMaterial, in: Capsule())
                .offset(y: -12)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            if isProcessingVoice {
                HStack(spacing: 6) {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text("Parsing...")
                        .font(.system(.caption, design: .rounded).weight(.semibold))
                        .foregroundColor(Color.IncomeGreen)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.ultraThinMaterial, in: Capsule())
                .offset(y: -12)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.3), value: speechRecognizer.isRecording)
        .animation(.easeInOut(duration: 0.3), value: isProcessingVoice)
        .fullScreenCover(isPresented: $addTransaction, onDismiss: {
            if confetti {
                if count != transactions.count {
                    counter += 1
                }
            }

            if firstLaunch {
                firstLaunch = false
            }

            voiceResults = nil

        }, content: {
            TransactionView(toEdit: nil, voiceResults: voiceResults)
        })
        .onChange(of: launchAdd) { _ in
            addTransaction = true
        }
        .onChange(of: addTransaction) { _ in
            if addTransaction {
                count = transactions.count
            }
        }
        .onChange(of: transactions.count) { _ in
            if !transactions.isEmpty {
                self.animate = false
            } else {
                self.animate = true
            }
        }
        .onChange(of: speechRecognizer.isRecording) { recording in
            if !recording && !speechRecognizer.transcript.isEmpty {
                processVoiceTranscript(speechRecognizer.transcript)
            }
        }
        .onOpenURL { url in
            guard
                url.host == "newExpense"

            else {
                return
            }

            addTransaction = true
        }
    }

    private func startVoiceRecording() {
        longPressTriggeredAt = Date()

        let impactMed = UIImpactFeedbackGenerator(style: .heavy)
        impactMed.impactOccurred()

        speechRecognizer.requestPermission { granted in
            if granted {
                speechRecognizer.startRecording()
            }
        }
    }

    private func processVoiceTranscript(_ text: String) {
        withAnimation {
            isProcessingVoice = true
        }

        let categoryNames = categories.map { $0.wrappedName }

        Task {
            do {
                let results = try await GeminiService.parseVoiceInput(text: text, categoryNames: categoryNames)

                await MainActor.run {
                    withAnimation {
                        isProcessingVoice = false
                    }

                    voiceResults = results
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        addTransaction = true
                    }
                }
            } catch {
                await MainActor.run {
                    withAnimation {
                        isProcessingVoice = false
                    }
                    // On error, still open TransactionView normally
                    addTransaction = true
                }
            }
        }
    }
}

struct MyButtonStyle: ButtonStyle {
    func makeBody(configuration: Self.Configuration) -> some View {
        configuration.label
            .font(.system(size: 20, weight: .bold))
            .foregroundColor(Color.LightIcon)
            .frame(width: 65, height: 38)
            .background(configuration.isPressed ? Color.SubtitleText : Color.DarkBackground, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
    }
}

struct BouncyButton: ButtonStyle {
    var duration: Double
    var scale: Double

    public func makeBody(configuration: Self.Configuration) -> some View {
        return configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
//            .scaleEffect(configuration.isPressed ? 1.3 : 1)
            .animation(.easeOut(duration: duration), value: configuration.isPressed)
    }
}

struct TabButton: View {
    var image: String
    var zoomed: Bool
    @Binding var currentTab: String

    var body: some View {
        Button {
            DispatchQueue.main.async {
                currentTab = image
            }
        } label: {
            Image(image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: 28, maxHeight: 28)
                .animation(.easeInOut(duration: 0.3), value: currentTab)
                .frame(maxWidth: .infinity)
                .foregroundColor(currentTab == image ? Color.DarkIcon : Color.GreyIcon)
        }
        .buttonStyle(BouncyButton(duration: 0.3, scale: 0.6))
        .accessibilityLabel("\(image) tab")
        .accessibilityAddTraits(
            currentTab == image
                ? [.isButton, .isSelected]
                : .isButton
        )
    }
}
