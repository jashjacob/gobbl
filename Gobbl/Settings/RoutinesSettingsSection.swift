import GobblCore
import SwiftUI

/// Settings → Briefs and nudges.
struct RoutinesSettingsSection: View {
    @AppStorage(Routines.Keys.morning) private var morning = true
    @AppStorage(Routines.Keys.morningTime) private var morningMinute = 8 * 60
    @AppStorage(Routines.Keys.evening) private var evening = true
    @AppStorage(Routines.Keys.eveningTime) private var eveningMinute = 16 * 60 + 30
    @AppStorage(Routines.Keys.nudges) private var nudges = true

    var body: some View {
        Section {
            HStack {
                Toggle("Morning brief", isOn: $morning)
                Spacer()
                DatePicker("", selection: time($morningMinute), displayedComponents: .hourAndMinute)
                    .labelsHidden()
                    .disabled(!morning)
            }
            HStack {
                Toggle("Evening wrap", isOn: $evening)
                Spacer()
                DatePicker("", selection: time($eveningMinute), displayedComponents: .hourAndMinute)
                    .labelsHidden()
                    .disabled(!evening)
            }
            Toggle(isOn: $nudges) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Nudges")
                    Text("A meeting about to start, an agent waiting on you. At most three a day, never in quiet mode or during focus.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Briefs and nudges")
        } footer: {
            Text("Briefs use your calendar, reminders, agent tasks and focus sessions, and need AI turned on. Say \"brief me\" in Chat any time.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    /// Minutes after midnight as a Date for the picker.
    private func time(_ minutes: Binding<Int>) -> Binding<Date> {
        Binding {
            Calendar.current.date(bySettingHour: minutes.wrappedValue / 60, minute: minutes.wrappedValue % 60, second: 0, of: Date()) ?? Date()
        } set: { date in
            let c = Calendar.current.dateComponents([.hour, .minute], from: date)
            minutes.wrappedValue = (c.hour ?? 0) * 60 + (c.minute ?? 0)
        }
    }
}
