import SwiftUI
import WatchKit
import UIKit
import UserNotifications

enum HxWatch {
    static let cyan = Color(red: 0.15, green: 0.82, blue: 0.93)
    static let blue = Color(red: 0.18, green: 0.36, blue: 0.8)
    static let orange = Color(red: 0.82, green: 0.4, blue: 0.24)
    static func name(_ object: WatchJSON) -> String { object["name"] as? String ?? "Exercise" }
    static func value(_ object: WatchJSON, _ key: String) -> String {
        WatchProtocol.number(object[key]).formatted(.number.precision(.fractionLength(0...1)))
    }
}

struct WatchHomeView: View {
    @EnvironmentObject var store: WatchStore
    @State private var path: [String] = []
    var body: some View {
        NavigationStack(path: $path) {
            List {
                Button { store.requestSync() } label: {
                    Label { Text(store.status).font(.caption2) } icon: { Image(systemName: "arrow.triangle.2.circlepath") }
                }
                if store.active != nil { tile("Active workout", icon: "figure.strengthtraining.traditional", route: "active", color: .green) }
                tile("Workouts", icon: "dumbbell.fill", route: "workouts", color: HxWatch.blue)
                tile("Nutrition", icon: "fork.knife", route: "nutrition", color: HxWatch.orange)
                tile("Fasting", icon: "timer", route: "fasting", color: .purple)
                tile("CNS readiness", icon: "heart.fill", route: "cns", color: .green)
                tile("Weekly volume", icon: "chart.bar.fill", route: "volume", color: HxWatch.blue)
                tile("Rambler", icon: "mic.fill", route: "rambler", color: HxWatch.orange)
                tile("Now Playing", icon: "music.note", route: "music", color: .pink)
                if store.summary != nil { tile("Last workout", icon: "checkmark.circle", route: "summary", color: .green) }
                NavigationLink("Settings") { WatchSettingsView() }
            }
            .navigationTitle("Herculex")
            .navigationDestination(for: String.self) { route in
                switch route {
                case "workouts": WatchWorkoutsView()
                case "active": WatchActiveWorkoutView()
                case "nutrition": WatchNutritionView()
                case "fasting": WatchFastingView()
                case "cns": WatchCnsView()
                case "volume": WatchVolumeView()
                case "rambler": WatchRamblerView()
                case "music": NowPlayingView().ignoresSafeArea()
                case "summary": WatchSummaryView()
                default: WatchNutritionView()
                }
            }
            .onOpenURL { url in
                guard url.scheme == "herculex" else { return }
                path = [url.host ?? "nutrition"]
            }
            .alert("Herculex", isPresented: Binding(get: { store.notice != nil }, set: { if !$0 { store.notice = nil } })) {
                Button("OK") { store.notice = nil }
            } message: { Text(store.notice ?? "") }
        }
    }
    private func tile(_ title: String, icon: String, route: String, color: Color) -> some View {
        NavigationLink(value: route) {
            Label(title, systemImage: icon).font(.headline).padding(.vertical, 8)
        }.listRowBackground(RoundedRectangle(cornerRadius: 22).fill(color.gradient))
    }
}

struct WatchWorkoutsView: View {
    @EnvironmentObject var store: WatchStore
    @State private var folder = "All"
    var body: some View {
        List {
            if store.active != nil { NavigationLink("Resume workout") { WatchActiveWorkoutView() } }
            NavigationLink { WatchStartWorkoutView(template: nil) } label: { Label("Free workout", systemImage: "plus") }
            if store.workouts.isEmpty { Text("Open Herculex on iPhone and sync your routines.").font(.footnote) }
            let folders = Array(Set(store.workouts.compactMap { $0["folderName"] as? String })).sorted()
            if !folders.isEmpty {
                Picker("Folder", selection: $folder) {
                    Text("All").tag("All")
                    ForEach(folders, id: \.self) { Text($0).tag($0) }
                }
            }
            ForEach(Array(store.workouts.filter { folder == "All" || $0["folderName"] as? String == folder }.enumerated()), id: \.offset) { _, template in
                NavigationLink { WatchStartWorkoutView(template: template) } label: {
                    VStack(alignment: .leading) {
                        if store.isToday(template) { Text("TODAY").font(.caption2).foregroundStyle(HxWatch.cyan) }
                        Text(HxWatch.name(template))
                        if let folderName = template["folderName"] as? String { Text(folderName).font(.caption2).foregroundStyle(.secondary) }
                        Text("\((template["exercises"] as? [WatchJSON] ?? []).count) exercises").font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
        }.navigationTitle("Workouts")
    }
}

struct WatchStartWorkoutView: View {
    @EnvironmentObject var store: WatchStore
    let template: WatchJSON?
    var body: some View {
        List {
            Text(template.map(HxWatch.name) ?? "Free workout").font(.headline)
            ForEach(Array((template?["exercises"] as? [WatchJSON] ?? []).enumerated()), id: \.offset) { _, exercise in
                VStack(alignment: .leading) {
                    Text(HxWatch.name(exercise))
                    Text("\(WatchProtocol.int(exercise["targetSets"])) sets").font(.caption2).foregroundStyle(.secondary)
                }
            }
            if store.active == nil {
                Button("Start workout") {
                    store.start(template)
                    UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
                }.tint(.green)
            }
            if store.active != nil { NavigationLink("Open workout") { WatchActiveWorkoutView() } }
        }
    }
}

struct WatchActiveWorkoutView: View {
    @EnvironmentObject var store: WatchStore
    @ObservedObject private var health = WorkoutHealth.shared
    @State private var finishPrompt = false
    @State private var discardPrompt = false
    var body: some View {
        List {
            if store.active != nil {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    VStack {
                        Text(Date(timeIntervalSince1970: WatchProtocol.number(store.payload["startedAtEpochMs"]) / 1000), style: .timer)
                            .font(.title2.monospacedDigit()).foregroundStyle(HxWatch.cyan)
                        Text(health.heartRate > 0 ? "♥ \(Int(health.heartRate)) bpm · \(Int(health.energy)) kcal" : "Heart rate —")
                            .font(.caption2).foregroundStyle(.secondary)
                        if let end = store.restEnd, end > context.date {
                            Text(timerInterval: context.date...end, countsDown: true).foregroundStyle(.green)
                            Button("Skip rest") { store.cancelRest() }.font(.caption2)
                        }
                    }
                }
                ForEach(Array(store.exercises.enumerated()), id: \.offset) { index, exercise in
                    NavigationLink { WatchExerciseView(index: index) } label: {
                        VStack(alignment: .leading) {
                            Text(HxWatch.name(WatchProtocol.json(exercise["template"])))
                            let sets = exercise["sets"] as? [WatchJSON] ?? []
                            Text("\(sets.filter { $0["completed"] as? Bool == true }.count)/\(sets.count) sets")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
                NavigationLink("Add exercise") { WatchCatalogView(replacing: nil) }
                NavigationLink("Rest timer") { WatchRestView() }
                NavigationLink("Music") { NowPlayingView().ignoresSafeArea() }
                Button("Finish workout") { finishPrompt = true }.tint(.green)
                Button("Discard workout", role: .destructive) { discardPrompt = true }
            } else {
                Text("Workout finished")
                NavigationLink("Summary") { WatchSummaryView() }
            }
        }
        .navigationTitle("Workout")
        .confirmationDialog("Save workout", isPresented: $finishPrompt) {
            Button("Finish") { store.finish(discard: false) }
            Button("Finish & save routine") { store.finish(discard: false, saveTemplate: true) }
        }
        .confirmationDialog("Discard this workout?", isPresented: $discardPrompt) {
            Button("Discard", role: .destructive) { store.finish(discard: true) }
        }
    }
}

struct WatchExerciseView: View {
    @EnvironmentObject var store: WatchStore
    let index: Int
    @State private var removing = false
    var body: some View {
        List {
            if store.exercises.indices.contains(index) {
                let exercise = store.exercises[index]
                let template = WatchProtocol.json(exercise["template"])
                ExerciseArtworkView(slug: template["slug"] as? String)
                Text(HxWatch.name(template)).font(.headline)
                ForEach(Array((exercise["sets"] as? [WatchJSON] ?? []).enumerated()), id: \.offset) { setIndex, set in
                    NavigationLink { WatchSetView(exerciseIndex: index, setIndex: setIndex, initial: set, template: template) } label: {
                        HStack {
                            Image(systemName: set["completed"] as? Bool == true ? "checkmark.circle.fill" : "circle").foregroundStyle(HxWatch.cyan)
                            VStack(alignment: .leading) {
                                Text("Set \(setIndex + 1) · \(set["setType"] as? String ?? "standard")").font(.caption)
                                Text("\(HxWatch.value(set, "weight")) kg × \(HxWatch.value(set, "reps"))").font(.headline)
                                if set["completed"] as? Bool != true {
                                    Text("Target \(HxWatch.value(set, "targetWeightKg")) × \(HxWatch.value(set, "targetReps"))").font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .swipeActions { Button("Delete", role: .destructive) {
                        store.mutateExercises { list in
                            var sets = list[index]["sets"] as? [WatchJSON] ?? []
                            sets.remove(at: setIndex); list[index]["sets"] = sets
                        }
                    } }
                }
                Button("Add set") { store.appendSet(index) }
                NavigationLink("Replace exercise") { WatchCatalogView(replacing: index) }
                Button("Remove exercise", role: .destructive) { removing = true }
            }
        }.navigationTitle("Exercise")
            .confirmationDialog("Remove exercise?", isPresented: $removing) {
                Button("Remove", role: .destructive) { store.mutateExercises { $0.remove(at: index) } }
            }
    }
}

struct ExerciseArtworkView: View {
    let slug: String?
    var body: some View {
        if let slug = slug, let url = Bundle.main.url(forResource: slug, withExtension: "png", subdirectory: "ExerciseArtwork"),
           let image = UIImage(contentsOfFile: url.path) {
            Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 130).accessibilityHidden(true)
        }
    }
}

struct WatchCatalogView: View {
    @EnvironmentObject var store: WatchStore
    @Environment(\.dismiss) private var dismiss
    let replacing: Int?
    @State private var search = ""
    var body: some View {
        List {
            TextField("Search exercises", text: $search)
            if store.catalog.isEmpty { Text("Sync the exercise library from iPhone first.").font(.footnote) }
            ForEach(Array(store.catalog.filter { search.isEmpty || HxWatch.name($0).localizedCaseInsensitiveContains(search) }.enumerated()), id: \.offset) { _, item in
                NavigationLink { WatchEquipmentView(template: item, replacing: replacing) } label: { Text(HxWatch.name(item)) }
            }
        }.navigationTitle("Exercises")
    }
}

struct WatchEquipmentView: View {
    @EnvironmentObject var store: WatchStore
    @Environment(\.dismiss) private var dismiss
    let template: WatchJSON
    let replacing: Int?
    @State private var equipment = ""
    var body: some View {
        List {
            Text(HxWatch.name(template))
            let choices = template["equipmentOptions"] as? [String] ?? []
            if !choices.isEmpty {
                Picker("Equipment", selection: $equipment) {
                    Text("Default").tag("")
                    ForEach(choices, id: \.self) { Text($0).tag($0) }
                }
            }
            Button("Add to workout") {
                var item = template
                if !equipment.isEmpty { item["equipmentVariant"] = equipment }
                store.addExercise(item, replacing: replacing)
                dismiss()
            }
        }
    }
}

struct CrownNumber: View {
    let title: String
    @Binding var value: Double
    var step: Double = 1
    var maximum: Double = 9999
    var minimum: Double = 0
    var body: some View {
        VStack {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            Text(value.formatted(.number.precision(.fractionLength(0...2)))).font(.title3.monospacedDigit())
            HStack {
                Button { value = max(minimum, value - step) } label: { Image(systemName: "minus") }
                Button { value = min(maximum, value + step) } label: { Image(systemName: "plus") }
            }.buttonStyle(.bordered)
        }
        .focusable()
        .digitalCrownRotation($value, from: minimum, through: maximum, by: step,
                              sensitivity: .medium, isContinuous: false, isHapticFeedbackEnabled: true)
        .accessibilityLabel(title)
    }
}

struct WatchSetView: View {
    @EnvironmentObject var store: WatchStore
    @Environment(\.dismiss) private var dismiss
    let exerciseIndex: Int
    let setIndex: Int
    let initial: WatchJSON
    let template: WatchJSON
    @State private var values: WatchJSON
    @State private var setType: String
    @State private var warmup: Bool
    @State private var accessory: String
    @State private var metadata: WatchJSON
    init(exerciseIndex: Int, setIndex: Int, initial: WatchJSON, template: WatchJSON) {
        self.exerciseIndex = exerciseIndex; self.setIndex = setIndex; self.initial = initial; self.template = template
        var values = initial
        if initial["completed"] as? Bool != true {
            for (actual, target) in [("weight", "targetWeightKg"), ("reps", "targetReps"), ("distanceM", "targetDistanceM"), ("rpe", "targetRpe")] {
                if WatchProtocol.number(values[actual]) == 0, let proposed = initial[target] { values[actual] = proposed }
            }
        }
        _values = State(initialValue: values)
        _setType = State(initialValue: initial["setType"] as? String ?? "standard")
        _warmup = State(initialValue: initial["isWarmup"] as? Bool ?? false)
        _accessory = State(initialValue: initial["accessory"] as? String ?? "")
        _metadata = State(initialValue: WatchProtocol.decode(initial["setTypeMetaJson"]))
    }
    private let types = ["standard", "drop", "rest_pause", "partials", "myo_reps", "pyramid", "forced", "cheat", "negatives", "pause", "mechanical_drop", "giant", "pre_exhaustion", "twenty_ones", "volume_20x60", "down_sets", "amrap", "emom", "for_time"]
    private var metric: String { template["loggingMetric"] as? String ?? "weight_reps" }
    var body: some View {
        List {
            Text(HxWatch.name(template)).font(.caption)
            if metric.contains("weight") { number(template["loadIsAssistance"] as? Bool == true ? "Assistance · kg" : "Weight · kg", key: "weight", step: 0.5) }
            if metric.contains("reps") { number("Repetitions", key: "reps") }
            if metric.contains("time") { number("Duration · seconds", key: "durationSeconds") }
            if metric.contains("time") {
                if let started = metadata["watchTimerStartedAtEpochMs"] as? NSNumber {
                    Text(Date(timeIntervalSince1970: started.doubleValue / 1000 - WatchProtocol.number(values["durationSeconds"])), style: .timer)
                        .font(.title3.monospacedDigit())
                    Button("Stop exercise timer") { stopTimer(); persistProgress() }
                } else {
                    Button("Start exercise timer") { metadata["watchTimerStartedAtEpochMs"] = WatchProtocol.now; persistProgress() }
                }
            }
            if metric.contains("distance") { number("Distance · metres", key: "distanceM", step: 5) }
            if metric.contains("calories") {
                CrownNumber(title: "Calories", value: Binding(get: { WatchProtocol.number(metadata["calories"]) }, set: { metadata["calories"] = $0 }))
            }
            Picker("Set type", selection: $setType) { ForEach(types, id: \.self) { Text($0.replacingOccurrences(of: "_", with: " ")).tag($0) } }
            Toggle("Warm up", isOn: $warmup)
            number("RPE · 0 = unset", key: "rpe", step: 0.5, maximum: 10)
            DisclosureGroup("Load details") {
                number("Bodyweight · kg", key: "bodyweightKg", step: 0.5)
                number("Chains · kg", key: "chainsKg", step: 0.5)
                TextField("Accessory / band", text: $accessory)
            }
            if ["rest_pause", "myo_reps"].contains(setType) {
                Button("Add mini-set") {
                    var mini = metadata["miniSets"] as? [Int] ?? []; mini.append(3); metadata["miniSets"] = mini
                }
                ForEach(Array((metadata["miniSets"] as? [Int] ?? []).enumerated()), id: \.offset) { index, _ in
                    CrownNumber(title: "Mini-set \(index + 1)", value: Binding(get: { Double((metadata["miniSets"] as? [Int] ?? [])[index]) }, set: {
                        var mini = metadata["miniSets"] as? [Int] ?? []; mini[index] = Int($0); metadata["miniSets"] = mini
                    }), maximum: 100)
                }
                Button("Remove last mini-set") {
                    var mini = metadata["miniSets"] as? [Int] ?? []
                    if !mini.isEmpty { mini.removeLast(); metadata["miniSets"] = mini }
                }
            }
            if ["forced", "cheat", "myo_reps"].contains(setType) {
                Button("Add extra reps") {
                    var reps = metadata["extraReps"] as? [Int] ?? metadata["forcedReps"] as? [Int] ?? metadata["cheatReps"] as? [Int] ?? []
                    reps.append(1); metadata["extraReps"] = reps
                }
                ForEach(Array((metadata["extraReps"] as? [Int] ?? []).enumerated()), id: \.offset) { index, _ in
                    CrownNumber(title: "Extra reps \(index + 1)", value: Binding(get: {
                        let reps = metadata["extraReps"] as? [Int] ?? []
                        return reps.indices.contains(index) ? Double(reps[index]) : 0
                    }, set: {
                        var reps = metadata["extraReps"] as? [Int] ?? []
                        if reps.indices.contains(index) { reps[index] = Int($0); metadata["extraReps"] = reps }
                    }), maximum: 100)
                }
                Button("Remove last extra reps") {
                    var reps = metadata["extraReps"] as? [Int] ?? []
                    if !reps.isEmpty { reps.removeLast(); metadata["extraReps"] = reps }
                }
            }
            ForEach(metaKeys, id: \.self) { key in
                CrownNumber(title: key, value: Binding(get: { WatchProtocol.number(metadata[key]) }, set: { metadata[key] = $0 }))
            }
            Button("Complete set") { save(completed: true) }.tint(.green)
            Button("Save changes") { save(completed: initial["completed"] as? Bool ?? false) }
            if initial["completed"] as? Bool == true { Button("Mark incomplete") { save(completed: false) } }
        }.navigationTitle("Set \(setIndex + 1)")
    }
    private var metaKeys: [String] {
        switch setType {
        case "drop": return ["dropPercent", "drops"]
        case "rest_pause": return ["restSeconds"]
        case "myo_reps": return ["activationReps"]
        case "pause": return ["pauseSeconds"]
        case "volume_20x60": return ["percent"]
        case "down_sets": return ["startReps", "decrement"]
        case "amrap": return ["capSeconds", "rounds"]
        case "emom": return ["minutes", "repsPerMinute"]
        case "for_time": return ["elapsedSeconds"]
        default: return []
        }
    }
    private func number(_ title: String, key: String, step: Double = 1, maximum: Double = 9999) -> some View {
        CrownNumber(title: title, value: Binding(get: { WatchProtocol.number(values[key]) }, set: { values[key] = $0 }), step: step, maximum: maximum)
    }
    private func save(completed: Bool) {
        if completed { stopTimer() }
        values["setType"] = setType; values["isWarmup"] = warmup
        values["accessory"] = accessory.isEmpty ? nil : accessory
        values["setTypeMetaJson"] = WatchProtocol.encode(metadata)
        store.saveSet(exercise: exerciseIndex, index: setIndex, set: values, completed: completed)
        dismiss()
    }
    private func stopTimer() {
        if let started = metadata["watchTimerStartedAtEpochMs"] as? NSNumber {
            values["durationSeconds"] = WatchProtocol.number(values["durationSeconds"]) + max(0, (Double(WatchProtocol.now) - started.doubleValue) / 1000).rounded()
            metadata.removeValue(forKey: "watchTimerStartedAtEpochMs")
        }
    }
    private func persistProgress() {
        values["setTypeMetaJson"] = WatchProtocol.encode(metadata)
        store.saveSet(exercise: exerciseIndex, index: setIndex, set: values, completed: initial["completed"] as? Bool ?? false)
    }
}

struct WatchRestView: View {
    @EnvironmentObject var store: WatchStore
    @State private var seconds: Double = 90
    var body: some View {
        List {
            CrownNumber(title: "Rest · seconds", value: $seconds, step: 15, maximum: 600, minimum: 15)
            Button("Start rest") { store.startRest(seconds: Int(seconds)) }
            Button("Cancel rest") { store.cancelRest() }
        }.navigationTitle("Rest")
    }
}

struct WatchNutritionView: View {
    @EnvironmentObject var store: WatchStore
    var body: some View {
        List {
            ForEach([("Calories", "calories", "calorie_goal"), ("Protein", "protein", "protein_goal"), ("Carbs", "carbs", "carbs_goal"), ("Fat", "fats", "fat_goal"), ("Water · ml", "water_ml", "water_goal")], id: \.0) { title, key, goal in
                NavigationLink { WatchNutrientTrendView(nutrient: key) } label: {
                    VStack(alignment: .leading) {
                        Text(title).font(.caption)
                        Text("\(Int(store.macroValue(key))) / \(HxWatch.value(store.macros, goal))").font(.headline)
                        ProgressView(value: min(1, store.macroValue(key) / max(1, WatchProtocol.number(store.macros[goal]))))
                    }
                }
            }
            NavigationLink("Log food or recipe") { WatchQuickFoodView() }
            NavigationLink("Quick calories & macros") { WatchQuickMacrosView(water: false) }
            NavigationLink("Add water") { WatchQuickMacrosView(water: true) }
            NavigationLink("Rambler · voice or text") { WatchRamblerView() }
        }.navigationTitle("Nutrition")
    }
}

struct WatchQuickMacrosView: View {
    @EnvironmentObject var store: WatchStore
    let water: Bool
    @State private var amount: Double = 250
    @State private var protein: Double = 0
    @State private var carbs: Double = 0
    @State private var fats: Double = 0
    var body: some View {
        List {
            CrownNumber(title: water ? "Water · ml" : "Calories · kcal", value: $amount, step: water ? 50 : 10)
            if !water {
                CrownNumber(title: "Protein · g", value: $protein)
                CrownNumber(title: "Carbs · g", value: $carbs)
                CrownNumber(title: "Fat · g", value: $fats)
            }
            Button("Save") {
                store.command("macroCommand", values: water ? ["kind": "water", "waterMl": Int(amount)] :
                                ["kind": "food", "calories": Int(amount), "protein": Int(protein), "carbs": Int(carbs), "fats": Int(fats)])
            }
        }.navigationTitle(water ? "Water" : "Quick add")
    }
}

struct WatchQuickFoodView: View {
    @EnvironmentObject var store: WatchStore
    @State private var category = "suggested"
    var body: some View {
        List {
            Picker("Show", selection: $category) {
                Text("Suggested").tag("suggested"); Text("Recent").tag("recent"); Text("Recipes").tag("recipes")
            }
            let items = store.quickadd[category] as? [WatchJSON] ?? []
            if items.isEmpty { Text("No items cached. Sync with iPhone.").font(.footnote) }
            ForEach(Array(items.enumerated()), id: \.offset) { _, food in
                NavigationLink { WatchFoodPortionView(food: food) } label: {
                    VStack(alignment: .leading) {
                        Text(HxWatch.name(food))
                        Text("\(HxWatch.value(food, "kcal")) kcal · \(food["portionLabel"] as? String ?? "portion")").font(.caption2)
                    }
                }
            }
        }.navigationTitle("Food")
    }
}

struct WatchFoodPortionView: View {
    @EnvironmentObject var store: WatchStore
    let food: WatchJSON
    @State private var multiplier: Double = 1
    @State private var meal = "snack"
    var body: some View {
        List {
            Text(HxWatch.name(food))
            CrownNumber(title: "Portions", value: $multiplier, step: 0.25, maximum: 50, minimum: 0.25)
            Picker("Meal", selection: $meal) {
                ForEach(Array((store.quickadd["mealSlots"] as? [WatchJSON] ?? []).enumerated()), id: \.offset) { _, slot in
                    Text(slot["label"] as? String ?? "Meal").tag(slot["key"] as? String ?? "snack")
                }
            }
            Text("\(Int(WatchProtocol.number(food["kcal"]) * multiplier)) kcal").foregroundStyle(HxWatch.cyan)
            Button("Log food") {
                var values: WatchJSON = ["mealKey": meal, "foodId": food["foodId"] ?? 0,
                                         "portionAmount": WatchProtocol.number(food["portionAmount"]) * multiplier,
                                         "portionUnit": food["portionUnit"] ?? "g"]
                if let recipe = food["recipeId"] { values["recipeId"] = recipe; values["portionAmount"] = multiplier }
                store.command("quickaddCommand", values: values)
            }
        }.onAppear { meal = food["lastMealKey"] as? String ?? (store.quickadd["mealSlots"] as? [WatchJSON])?.first?["key"] as? String ?? "snack" }
    }
}

struct WatchRamblerView: View {
    @EnvironmentObject var store: WatchStore
    @State private var text = ""
    @State private var meal = "lunch"
    var body: some View {
        List {
            Text("Describe your food").font(.headline)
            TextField("Type or dictate", text: $text)
            Text("Use the microphone in the text input to dictate.").font(.caption2).foregroundStyle(.secondary)
            Picker("Meal", selection: $meal) {
                ForEach(["breakfast", "lunch", "dinner", "snack"], id: \.self) { Text($0.capitalized).tag($0) }
            }
            Button("Send to Rambler") {
                store.command("ramblerCommand", values: ["text": text, "mealKey": meal]); text = ""
            }.disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            Text("Saved requests wait for iPhone. AI analysis needs internet.").font(.caption2).foregroundStyle(.secondary)
        }.navigationTitle("Rambler")
    }
}

struct WatchFastingView: View {
    @EnvironmentObject var store: WatchStore
    @State private var hours: Double = 16
    @State private var stop = false
    var body: some View {
        List {
            if store.fasting["hasActiveFast"] as? Bool == true {
                let start = Date(timeIntervalSince1970: WatchProtocol.number(store.fasting["startedAtEpochMs"]) / 1000)
                Text(start, style: .timer).font(.title2.monospacedDigit()).foregroundStyle(.purple)
                Text("Goal · \(Int(WatchProtocol.number(store.fasting["targetSeconds"]) / 3600))h")
                TimelineView(.periodic(from: .now, by: 60)) { context in
                    let elapsed = Int(context.date.timeIntervalSince(start) / 3600)
                    let stages = WatchProtocol.array(loadStages())
                    if let stage = stages.last(where: { WatchProtocol.int($0["hour"]) <= elapsed }) {
                        Text(stage["stageName"] as? String ?? "Fasting").font(.headline)
                        Text(stage["shortMessage"] as? String ?? "").font(.caption2)
                    }
                }
                Button("End fast") { stop = true }.tint(.orange)
            } else {
                CrownNumber(title: "Goal · hours", value: $hours, maximum: 72, minimum: 1)
                Button("Start fast") { store.toggleFast(hours: Int(hours)) }.tint(.purple)
                if let next = store.fasting["nextFastEpochMs"] as? NSNumber {
                    Text("Next: " + Date(timeIntervalSince1970: next.doubleValue / 1000).formatted()).font(.caption2)
                }
                let duration = WatchProtocol.int(store.fasting["lastFastDurationSeconds"])
                if duration > 0 { Text("Last fast · \(duration / 3600)h \(duration / 60 % 60)m").font(.caption2) }
            }
        }.navigationTitle("Fasting")
            .confirmationDialog("End this fast?", isPresented: $stop) { Button("End fast") { store.toggleFast(hours: Int(hours)) } }
    }
    private func loadStages() -> String {
        guard let url = Bundle.main.url(forResource: "fasting_stages", withExtension: "json"), let data = try? Data(contentsOf: url) else { return "[]" }
        return String(data: data, encoding: .utf8) ?? "[]"
    }
}

struct WatchCnsView: View {
    @EnvironmentObject var store: WatchStore
    var body: some View {
        let cns = WatchProtocol.json(store.cache["cns"])
        VStack(spacing: 12) {
            Image(systemName: "heart.fill").foregroundStyle(.green)
            Text("\(HxWatch.value(cns, "readiness_pct"))%").font(.largeTitle)
            Text(cns["status"] as? String ?? "Sync with iPhone").font(.headline)
            Text("CNS readiness").font(.caption2).foregroundStyle(.secondary)
        }.navigationTitle("CNS")
    }
}

struct WatchVolumeView: View {
    @EnvironmentObject var store: WatchStore
    var body: some View {
        List {
            Text("\(HxWatch.value(store.macros, "weekly_tonnage")) kg").font(.title3)
            Text("\(HxWatch.value(store.macros, "weekly_sets")) sets this week")
            ForEach(Array(WatchProtocol.array(store.macros["weekly_volume_json"]).enumerated()), id: \.offset) { _, row in
                VStack(alignment: .leading) {
                    Text(row["label"] as? String ?? row["muscle"] as? String ?? row["name"] as? String ?? "Volume")
                    Text("\(HxWatch.value(row, "sets")) sets · \(HxWatch.value(row, "tonnage")) kg").font(.caption2)
                }
            }
        }.navigationTitle("Weekly volume")
    }
}

struct WatchNutrientTrendView: View {
    @EnvironmentObject var store: WatchStore
    let nutrient: String
    var body: some View {
        List {
            ForEach(Array(WatchProtocol.array(store.macros["nutrient_trends_json"]).enumerated()), id: \.offset) { _, day in
                HStack {
                    Text(day["day"] as? String ?? day["date"] as? String ?? "")
                    Spacer(); Text(HxWatch.value(day, nutrient == "water_ml" ? "water" : nutrient))
                }.font(.caption)
            }
        }.navigationTitle(nutrient.capitalized)
    }
}

struct WatchSummaryView: View {
    @EnvironmentObject var store: WatchStore
    var body: some View {
        let body = store.summary.map(WatchProtocol.payload) ?? [:]
        let exercises = body["exercises"] as? [WatchJSON] ?? []
        List {
            Text(HxWatch.name(WatchProtocol.json(body["template"]))).font(.headline)
            let seconds = max(0, Int((WatchProtocol.number(body["endedAtEpochMs"]) - WatchProtocol.number(body["startedAtEpochMs"])) / 1000))
            Text("\(seconds / 60) min · \(HxWatch.value(body, "activeEnergyKcal")) kcal")
            Text("\(exercises.count) exercises · \(exercises.flatMap { $0["sets"] as? [WatchJSON] ?? [] }.filter { $0["completed"] as? Bool == true }.count) sets")
            Text(WorkoutHealth.shared.availability).font(.caption2).foregroundStyle(.secondary)
            Text(store.status).font(.caption2)
        }.navigationTitle("Summary")
    }
}

struct WatchSettingsView: View {
    @EnvironmentObject var store: WatchStore
    var body: some View {
        List {
            Text(store.status).font(.caption2)
            Button("Sync with iPhone") { store.requestSync() }
            Button("Enable rest alerts") { UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in } }
            Text("Apple Health access can be changed in Settings → Health. Manual workout logging works without it.").font(.caption2)
        }.navigationTitle("Settings")
    }
}
