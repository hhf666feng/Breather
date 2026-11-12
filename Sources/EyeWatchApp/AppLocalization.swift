import SwiftUI
import EyeWatchCore

private struct MujianLanguageKey: EnvironmentKey {
    static let defaultValue: AppLanguage = .chinese
}

extension EnvironmentValues {
    var mujianLanguage: AppLanguage {
        get { self[MujianLanguageKey.self] }
        set { self[MujianLanguageKey.self] = newValue }
    }
}

@MainActor
struct LanguageRoot<Content: View>: View {
    @ObservedObject var model: AppModel
    let content: Content
    init(model: AppModel, @ViewBuilder content: () -> Content) {
        self.model = model
        self.content = content()
    }
    var body: some View {
        content
            .environment(\.mujianLanguage, model.settings.language)
            .environment(\.locale, model.settings.language.locale)
    }
}
