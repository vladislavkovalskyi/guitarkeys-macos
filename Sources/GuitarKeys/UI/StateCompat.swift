import SwiftUI

/// `@State` в SDK macOS 26+ объявлен макросом, а плагин `SwiftUIMacros` поставляется
/// только вместе с Xcode — в Command Line Tools его нет. Сама обёртка `State`
/// никуда не делась, поэтому обращаемся к ней под именем, которое макрос не перехватывает.
/// Поведение, включая проекцию `$value` в `Binding`, полностью совпадает с `@State`.
typealias UIState<Value> = State<Value>
