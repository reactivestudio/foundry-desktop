import SwiftUI

struct ShadowCastersKey: PreferenceKey {
    static let defaultValue: [ShadowCaster] = []
    static func reduce(value: inout [ShadowCaster], nextValue: () -> [ShadowCaster]) {
        value.append(contentsOf: nextValue())
    }
}
