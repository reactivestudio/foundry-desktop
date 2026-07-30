import Core
import SwiftUI

/// Тумблер-индикатор 31×18: канавка всегда вдавлена, объём по свету; своего
/// клика нет — мишень по Фитсу вся строка.
struct OBToggle: View {
    let isOn: Bool
    var body: some View {
        ZStack(alignment: isOn ? .trailing : .leading) {
            Capsule()
                .fill(isOn ? OB.ultramarine : Color.white.opacity(0.11))
                .overlay(Capsule().strokeBorder(.white.opacity(0.05), lineWidth: 0.5))
                .overlay(  // канавка вдавлена сверху
                    Capsule().stroke(.black.opacity(0.5), lineWidth: 1.5)
                        .blur(radius: 0.5).mask(Capsule().padding(.bottom, 8)))
            Circle()
                .fill(
                    LinearGradient(
                        colors: [.white, Color(hexValue: 0xE9EBEF)],
                        startPoint: .top, endPoint: .bottom)
                )
                .frame(width: 14, height: 14)
                .shadow(color: .black.opacity(0.55), radius: 1, y: 1)
                .padding(2)
        }
        .frame(width: 31, height: 18)
        .animation(OB.easeReal(0.30), value: isOn)
    }
}
