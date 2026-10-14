// Окно настройки кота: имя, характер, внешность и живое превью.

import AppKit
import SwiftUI

final class CatEditorModel: ObservableObject {
    @Published var config: CatConfig {
        didSet { onChange?(config) }
    }
    let isNew: Bool
    var onChange: ((CatConfig) -> Void)?
    var onSave: ((CatConfig) -> Void)?
    var onCancel: (() -> Void)?

    init(config: CatConfig, isNew: Bool) {
        self.config = config
        self.isNew = isNew
    }

    // Взять внешность и характер готового кота, сохранив своё имя
    func apply(_ preset: CatConfig) {
        var c = config
        c.look = preset.look
        c.personality = preset.personality
        c.female = preset.female
        if c.name.isEmpty || c.name == "Новый котик" || Presets.all.contains(where: { $0.name == c.name }) {
            c.name = preset.name
        }
        config = c
    }
}

struct CatEditorView: View {
    @ObservedObject var model: CatEditorModel

    func color(_ keyPath: WritableKeyPath<CatLook, RGBA>) -> Binding<CGColor> {
        Binding(
            get: { model.config.look[keyPath: keyPath].cg },
            set: { model.config.look[keyPath: keyPath] = RGBA(cg: $0) }
        )
    }

    var body: some View {
        HStack(alignment: .top, spacing: 20) {
            VStack(spacing: 12) {
                CatPreview(look: model.config.look)
                    .frame(width: 240, height: 200)
                    .background(RoundedRectangle(cornerRadius: 14).fill(Color(nsColor: .controlBackgroundColor)))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color(nsColor: .separatorColor)))

                Text(model.config.name.isEmpty ? "Без имени" : model.config.name)
                    .font(.title2.bold())
                Text(model.config.personality.summary)
                    .font(.callout)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(width: 240)
                    .fixedSize(horizontal: false, vertical: true)

                Menu("Взять за основу готового кота") {
                    ForEach(Presets.all) { preset in
                        Button("\(preset.name) — \(preset.personality.title.lowercased())") {
                            model.apply(preset)
                        }
                    }
                }
                .frame(width: 240)
            }

            VStack(alignment: .leading, spacing: 14) {
                Form {
                    Section(header: Text("Кто это").bold()) {
                        TextField("Имя", text: $model.config.name)
                        Picker("Пол", selection: $model.config.female) {
                            Text("Кот").tag(false)
                            Text("Кошка").tag(true)
                        }
                        .pickerStyle(.segmented)
                        Picker("Характер", selection: $model.config.personality) {
                            ForEach(Personality.allCases) { Text($0.title).tag($0) }
                        }
                    }

                    Section(header: Text("Внешность").bold()) {
                        ColorPicker("Шерсть", selection: color(\.fur), supportsOpacity: false)
                        Picker("Узор", selection: $model.config.look.pattern) {
                            ForEach(FurPattern.allCases) { Text($0.title).tag($0) }
                        }
                        ColorPicker("Цвет узора", selection: color(\.patternColor), supportsOpacity: false)
                            .disabled(model.config.look.pattern == .solid || model.config.look.pattern == .tuxedo)
                        ColorPicker("Животик", selection: color(\.belly), supportsOpacity: false)
                        ColorPicker("Глаза", selection: color(\.eyes), supportsOpacity: false)
                        Picker("Уши", selection: $model.config.look.ears) {
                            ForEach(EarStyle.allCases) { Text($0.title).tag($0) }
                        }
                        Picker("Размер", selection: $model.config.look.size) {
                            ForEach(BodySize.allCases) { Text($0.title).tag($0) }
                        }
                        Slider(value: $model.config.look.tail, in: 0.6...1.4) {
                            Text("Хвост")
                        } minimumValueLabel: {
                            Text("короткий").font(.caption)
                        } maximumValueLabel: {
                            Text("длинный").font(.caption)
                        }
                    }

                    Section(header: Text("Аксессуар").bold()) {
                        Picker("Аксессуар", selection: $model.config.look.accessory) {
                            ForEach(Accessory.allCases) { Text($0.title).tag($0) }
                        }
                        ColorPicker("Цвет аксессуара", selection: color(\.accessoryColor), supportsOpacity: false)
                            .disabled(model.config.look.accessory == .none)
                    }
                }
                .frame(width: 340)

                HStack {
                    Spacer()
                    Button("Отмена") { model.onCancel?() }
                        .keyboardShortcut(.cancelAction)
                    Button(model.isNew ? "Добавить на экран" : "Сохранить") { model.onSave?(model.config) }
                        .keyboardShortcut(.defaultAction)
                        .disabled(model.config.name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .padding(20)
    }
}

// Живое превью: кот по очереди стоит, гуляет на месте, радуется и спит
struct CatPreview: NSViewRepresentable {
    var look: CatLook

    func makeNSView(context: Context) -> CatPreviewView {
        let v = CatPreviewView(frame: .zero)
        v.look = look
        return v
    }

    func updateNSView(_ view: CatPreviewView, context: Context) {
        view.look = look
        view.needsDisplay = true
    }
}

final class CatPreviewView: NSView {
    var look: CatLook = Presets.murka.look
    var timer: Timer?
    let start = ProcessInfo.processInfo.systemUptime

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        timer?.invalidate()
        timer = nil
        guard window != nil else { return }
        let t = Timer(timeInterval: 1.0 / 30.0, target: self, selector: #selector(step), userInfo: nil, repeats: true)
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    @objc func step() {
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let t = ProcessInfo.processInfo.systemUptime - start
        let states: [PetState] = [.idle, .walk, .happy, .idle, .sleep]
        let state = states[Int(t / 3) % states.count]
        let pose = CatPose(
            state: state,
            time: t,
            facingRight: Int(t / 7.5) % 2 == 0,
            surface: .floor,
            onGround: true,
            lookX: CGFloat(sin(t * 0.8)) * 1.6,
            lookY: CGFloat(cos(t * 0.6)) * 0.8,
            blinking: t.truncatingRemainder(dividingBy: 3.7) < 0.15
        )
        CatRenderer.draw(look: look, pose: pose, in: bounds, baseY: 22, zoom: 1.6)
    }
}
