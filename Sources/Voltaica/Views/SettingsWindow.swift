import SwiftUI
import VoltaicaCore

struct SettingsWindow: View {
    @Environment(AppModel.self) private var model
    @Environment(Preferences.self) private var preferences
    @State private var showUninstallConfirmation = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Settings")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.top, 24)

                limitSection
                protectionSection
                automationSection
                appearanceSection
                advancedSection
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minWidth: 540, minHeight: 600)
        .background { AuroraBackdrop(colors: model.accentColors) }
        .preferredColorScheme(.dark)
        .confirmationDialog("Remove the background service?",
                            isPresented: $showUninstallConfirmation) {
            Button("Remove and hand the charger back", role: .destructive) {
                Task { await model.uninstallHelper() }
            }
        } message: {
            Text("Charging goes back to the way macOS handles it. Your settings are kept.")
        }
    }

    // MARK: - Sections

    private var limitSection: some View {
        Card(title: "Charge limit", icon: "bolt.horizontal") {
            Toggle("Hold the battery at a limit", isOn: Binding(
                get: { model.configuration.enabled },
                set: { value in model.edit { $0.enabled = value }; model.pushNow() }
            ))

            HStack {
                Text("Limit")
                ProLock(unlocked: model.features.customLimit)
                Spacer()
                Text("\(model.configuration.clampedLimit)%")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .monospacedDigit()
            }
            LimitSlider(value: Binding(get: { model.configuration.clampedLimit },
                                       set: { model.setLimit($0) }),
                        colors: model.accentColors,
                        onEditingChanged: { editing in
                            model.isDraggingLimit = editing
                            if !editing { model.pushNow() }
                        })
                .disabled(!model.configuration.enabled || !model.features.customLimit)
                .opacity(model.features.customLimit ? 1 : 0.45)

            Text("80% is the sweet spot for a Mac that lives on a desk. Below 60% there is little extra to gain, and you lose usable runtime.")
                .settingsCaption()

            Divider().overlay(Palette.hairline)

            HStack(spacing: 7) {
                Toggle("Sailing mode", isOn: Binding(
                    get: { model.configuration.sailingEnabled },
                    set: { value in
                        guard model.requireFeature(model.features.sailingMode) else { return }
                        model.edit { $0.sailingEnabled = value }
                        model.pushNow()
                    }
                ))
                ProLock(unlocked: model.features.sailingMode)
            }
            Text("Leaves the charger off while the battery drifts down, instead of nudging it back up every fraction of a percent. That is where the saved cycles come from.")
                .settingsCaption()

            if model.configuration.sailingEnabled {
                Stepper(value: Binding(get: { model.configuration.sailingDepth },
                                       set: { value in model.edit { $0.sailingDepth = value }; model.pushNow() }),
                        in: 1...20) {
                    Text("Resume charging \(model.configuration.sailingDepth)% below the limit")
                }
            }

            if model.capabilities.hasHardwareCeiling {
                Divider().overlay(Palette.hairline)
                Toggle("Firmware ceiling (about 80%)", isOn: Binding(
                    get: { model.configuration.hardwareCeilingEnabled },
                    set: { value in model.edit { $0.hardwareCeilingEnabled = value }; model.pushNow() }
                ))
                Text("Set inside the Mac itself, so it keeps working through reboots and even if Voltaica is removed. Coarse: it is a fixed ceiling, not a number you pick.")
                    .settingsCaption()
            }
        }
    }

    private var protectionSection: some View {
        Card(title: "Protection", icon: "shield.lefthalf.filled", unlocked: model.features.heatProtection) {
            Toggle("Pause charging when the battery is warm", isOn: Binding(
                get: { model.configuration.heatProtectionEnabled },
                set: { value in model.edit { $0.heatProtectionEnabled = value }; model.pushNow() }
            ))
            if model.configuration.heatProtectionEnabled {
                HStack {
                    Text("Above")
                    Slider(value: Binding(get: { model.configuration.heatThreshold },
                                          set: { value in model.edit { $0.heatThreshold = value.rounded() } }),
                           in: 30...50,
                           step: 1,
                           onEditingChanged: { editing in if !editing { model.pushNow() } })
                    Text(String(format: "%.0f°C", model.configuration.heatThreshold))
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .frame(width: 46, alignment: .trailing)
                }
                Text("Heat is what actually ages a lithium pack, more than the number of cycles. Charging while the Mac is already hot is the worst case.")
                    .settingsCaption()
            }

            Divider().overlay(Palette.hairline)

            Stepper(value: Binding(get: { model.configuration.dischargeFloor },
                                   set: { value in model.edit { $0.dischargeFloor = value }; model.pushNow() }),
                    in: 15...90) {
                Text("Never run the battery below \(model.configuration.dischargeFloor)%")
            }
            Text("Applies to anything that cuts adapter power on purpose. Voltaica also refuses to go under 15% whatever this says.")
                .settingsCaption()
        }
    }

    private var automationSection: some View {
        Card(title: "Automation", icon: "clock.arrow.2.circlepath", unlocked: model.features.schedules) {
            Toggle("Have it full by a set time", isOn: Binding(
                get: { model.configuration.scheduledTopUp.enabled },
                set: { value in model.edit { $0.scheduledTopUp.enabled = value }; model.pushNow() }
            ))

            if model.configuration.scheduledTopUp.enabled {
                HStack(spacing: 10) {
                    Stepper(value: Binding(get: { model.configuration.scheduledTopUp.hour },
                                           set: { value in model.edit { $0.scheduledTopUp.hour = value }; model.pushNow() }),
                            in: 0...23) {
                        Text("Ready by \(model.configuration.scheduledTopUp.timeLabel)")
                    }
                    Stepper("", value: Binding(get: { model.configuration.scheduledTopUp.minute },
                                               set: { value in model.edit { $0.scheduledTopUp.minute = value }; model.pushNow() }),
                            in: 0...55,
                            step: 5)
                        .labelsHidden()
                }
                WeekdayPicker(selection: Binding(
                    get: { model.configuration.scheduledTopUp.weekdays },
                    set: { value in model.edit { $0.scheduledTopUp.weekdays = value }; model.pushNow() }
                ), colors: model.accentColors)
                Text("Charging is allowed to run past the limit for the \(model.configuration.scheduledTopUp.leadMinutes) minutes before that time, so you leave the house full without sitting at 100% all night.")
                    .settingsCaption()
            }

            if model.canDischarge {
                Divider().overlay(Palette.hairline)
                Toggle("Run down to the limit instead of waiting", isOn: Binding(
                    get: { model.configuration.dischargeToLimitAutomatically },
                    set: { value in model.edit { $0.dischargeToLimitAutomatically = value }; model.pushNow() }
                ))
                Text("If you plug in at 100%, Voltaica cuts adapter power until the pack is back at the limit, instead of leaving it high for hours.")
                    .settingsCaption()
            }

            Divider().overlay(Palette.hairline)

            Toggle("Notify me about limits, top-ups and heat pauses", isOn: Binding(
                get: { model.configuration.notificationsEnabled },
                set: { value in model.edit { $0.notificationsEnabled = value }; model.pushNow() }
            ))
        }
    }

    private var appearanceSection: some View {
        Card(title: "Menu bar", icon: "menubar.rectangle") {
            Toggle("Show the percentage", isOn: Binding(
                get: { preferences.showPercentage },
                set: { preferences.showPercentage = $0 }
            ))
            Toggle("Colour the icon to match the state", isOn: Binding(
                get: { preferences.colouredIcon },
                set: { preferences.colouredIcon = $0 }
            ))
            Toggle("Use the hardware percentage", isOn: Binding(
                get: { preferences.showHardwarePercentage },
                set: { preferences.showHardwarePercentage = $0 }
            ))
            Text("macOS rounds the charge and pins it to 100% while the pack is trickle charging. The hardware figure is what the gas gauge actually reports, and it is the number the limit works on.")
                .settingsCaption()

            Divider().overlay(Palette.hairline)

            Toggle("Open Voltaica at login", isOn: Binding(
                get: { model.launchAtLogin },
                set: { model.launchAtLogin = $0 }
            ))
            Text("The charge limit is held by the background service and does not need the app to be running. This is only about the menu bar item.")
                .settingsCaption()
        }
    }

    private var advancedSection: some View {
        Card(title: "Advanced", icon: "wrench.and.screwdriver") {
            if model.capabilities.hasMagSafeLED {
                Toggle("Use the MagSafe light to show the state", isOn: Binding(
                    get: { model.configuration.magSafeFeedbackEnabled },
                    set: { value in model.edit { $0.magSafeFeedbackEnabled = value }; model.pushNow() }
                ))
                Text("Green while holding at the limit, amber while charging. Experimental: the light is driven by an SMC key whose values are not documented, so switch it off if the colours look wrong.")
                    .settingsCaption()
                Divider().overlay(Palette.hairline)
            }

            Stepper(value: Binding(get: { model.configuration.calibrationReminderDays },
                                   set: { value in model.edit { $0.calibrationReminderDays = value }; model.pushNow() }),
                    in: 14...180,
                    step: 7) {
                Text("Suggest a calibration every \(model.configuration.calibrationReminderDays) days")
            }

            Divider().overlay(Palette.hairline)

            HStack {
                Text("Background service")
                Spacer()
                Text(model.installState.rawValue)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(model.installState == .enabled ? Color(hex: 0x7BF0C0) : Color(hex: 0xFFD166))
            }
            HStack(spacing: 8) {
                if model.installState != .enabled {
                    Button("Install") { model.installHelper() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                }
                Button("Open Login Items") { model.openLoginItems() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                Button("Remove") { showUninstallConfirmation = true }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
    }
}

private struct Card<Content: View>: View {
    var title: String
    var icon: String
    /// nil for cards that are free; false marks a card the current license cannot use.
    var unlocked: Bool?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 7) {
                SectionLabel(title: title, systemImage: icon)
                if let unlocked { ProLock(unlocked: unlocked) }
                Spacer(minLength: 0)
            }
            content
                .toggleStyle(SwitchRow())
                .disabled(unlocked == false)
                .opacity(unlocked == false ? 0.45 : 1)
        }
        .font(.system(size: 12.5, design: .rounded))
        .foregroundStyle(.white.opacity(0.88))
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(cornerRadius: 20)
    }
}

private struct WeekdayPicker: View {
    @Binding var selection: Set<Int>
    var colors: [Color]

    private let labels = [(1, "S"), (2, "M"), (3, "T"), (4, "W"), (5, "T"), (6, "F"), (7, "S")]

    var body: some View {
        HStack(spacing: 5) {
            ForEach(labels, id: \.0) { day, label in
                let selected = selection.contains(day)
                Button {
                    if selected { selection.remove(day) } else { selection.insert(day) }
                } label: {
                    Text(label)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .frame(width: 26, height: 26)
                        .foregroundStyle(selected ? AnyShapeStyle(Color.black) : AnyShapeStyle(Color.white.opacity(0.6)))
                        .background {
                            Circle().fill(selected
                                          ? AnyShapeStyle(LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom))
                                          : AnyShapeStyle(Color.white.opacity(0.08)))
                        }
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
    }
}

extension Text {
    /// Explanatory copy under a control: quiet, small, and never more than a couple of lines.
    func settingsCaption() -> some View {
        font(.system(size: 10.5, design: .rounded))
            .foregroundStyle(.white.opacity(0.45))
            .fixedSize(horizontal: false, vertical: true)
    }
}
