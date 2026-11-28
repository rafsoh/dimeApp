//
//  KeyboardHeightHelper.swift
//  xpenz
//
//  Created by Rafael Soh on 16/5/22.
//

import Combine
import Foundation
import SwiftUI
import UIKit

class KeyboardHeightHelper: ObservableObject {
    @Published var keyboardHeight: CGFloat = 0

    private func listenForKeyboardNotifications() {
        NotificationCenter.default.addObserver(forName: UIResponder.keyboardDidShowNotification,
                                               object: nil,
                                               queue: .main) { notification in
            guard let userInfo = notification.userInfo,
                  let keyboardRect = userInfo[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }

            self.keyboardHeight = keyboardRect.height
        }

//        NotificationCenter.default.addObserver(forName: UIResponder.keyboardDidHideNotification,
//                                               object: nil,
//                                               queue: .main) { (notification) in
//                                                self.keyboardHeight = 0
//        }
    }

    init() {
        listenForKeyboardNotifications()
    }
}

extension Publishers {
    // 1.
    static var keyboardHeight: AnyPublisher<CGFloat, Never> {
        // 2.
        let willShow = NotificationCenter.default.publisher(for: UIApplication.keyboardWillShowNotification)
            .map { $0.keyboardHeight }

        let willHide = NotificationCenter.default.publisher(for: UIApplication.keyboardWillHideNotification)
            .map { _ in CGFloat(0) }

        // 3.
        return MergeMany(willShow, willHide)
            .eraseToAnyPublisher()
    }
}

extension Notification {
    var keyboardHeight: CGFloat {
        return (userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect)?.height ?? 0
    }

    var keyboardEndFrame: CGRect {
        (userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect) ?? .null
    }
}

extension View {
    func placeholder<Content: View>(
        when shouldShow: Bool,
        alignment: Alignment = .leading,
        @ViewBuilder placeholder: () -> Content
    ) -> some View {
        ZStack(alignment: alignment) {
            placeholder().opacity(shouldShow ? 1 : 0)
            self
        }
    }
}

extension UIApplication {
    func endEditing() {
        sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

final class KeyboardHeightCache {
    static let shared = KeyboardHeightCache()

    private var observer: NSObjectProtocol?
    private var frameObserver: NSObjectProtocol?

    /// Where the keyboard is or is heading, in screen coordinates. Off screen or `.null` while hidden.
    private(set) var screenFrame: CGRect = .null

    private static let defaults = UserDefaults(suiteName: "group.com.rafaelsoh.dime")

    /// The key window's size. It differs between the Duo's cover screen and its main screen, and between orientations.
    static var windowSize: CGSize? {
        UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow }
            .first?
            .bounds.size
    }

    private static func noteKeyboardKey(for size: CGSize) -> String {
        "noteKeyboard.\(Int(size.width.rounded()))x\(Int(size.height.rounded()))"
    }

    /// Saves the add page's note keyboard, which covers the number pad, for windows this size.
    static func recordNoteKeyboard(height: CGFloat) {
        guard height > 200, let size = windowSize else { return }
        defaults?.set(Double(height - 20), forKey: noteKeyboardKey(for: size))
    }

    /// How tall the number pad should be so the note's keyboard covers exactly it: the note keyboard's height last time
    /// in a window this size, or else the last keyboard's anywhere. 20 short of the keyboard, for the page's bottom padding.
    static func padHeight(fallback: Double) -> Double {
        guard let size = windowSize, let height = defaults?.object(forKey: noteKeyboardKey(for: size)) as? Double else {
            return fallback
        }
        return height
    }

    func start() {
        guard observer == nil else { return }

        observer = NotificationCenter.default.addObserver(forName: UIResponder.keyboardWillShowNotification, object: nil, queue: .main) { notification in
            let height = notification.keyboardHeight
            if height > 200 {
                UserDefaults(suiteName: "group.com.rafaelsoh.dime")?.set(Double(height - 20), forKey: "keyboard")
            }
        }

        frameObserver = NotificationCenter.default.addObserver(forName: UIResponder.keyboardWillChangeFrameNotification, object: nil, queue: .main) { [weak self] notification in
            self?.screenFrame = notification.keyboardEndFrame
        }
    }
}

struct KeyboardAwareModifier: ViewModifier {
    @AppStorage("keyboard", store: UserDefaults(suiteName: "group.com.rafaelsoh.dime")) var savedKeyboardHeight: Double = .init(UIScreen.main.bounds.height / 2.5)
    var showToolbar: Bool

    /// The height in use, and the window size it was read for. It's read when the pad appears and kept, so nothing on the
    /// page moves when a keyboard shows: following the saved height live resized the pad, and moved the page above it,
    /// whenever a keyboard wasn't the height of the one before, such as the first on the Duo's cover screen after one on
    /// its main screen. It's read again only for a new window size, such as after rotating.
    @State private var snapshot: (size: CGSize?, height: Double)?

    private var currentHeight: Double {
        KeyboardHeightCache.padHeight(fallback: savedKeyboardHeight)
    }

    func body(content: Content) -> some View {
        content
            .frame(height: snapshot?.height ?? currentHeight)
            .background(
                GeometryReader { proxy in
                    Color.clear
                        .onAppear {
                            if snapshot == nil {
                                snapshot = (KeyboardHeightCache.windowSize, currentHeight)
                            }
                        }
                        .onChange(of: proxy.size.width) { _ in
                            let size = KeyboardHeightCache.windowSize
                            if snapshot?.size != size {
                                snapshot = (size, currentHeight)
                            }
                        }
                }
            )
    }
}

extension View {
    func keyboardAwareHeight(showToolbar: Bool) -> some View {
        ModifiedContent(content: self, modifier: KeyboardAwareModifier(showToolbar: showToolbar))
    }
}
