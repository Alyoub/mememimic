import SwiftUI
import UIKit

/// Bright candy colors derived from the icon and splash. Each player uses one as their
/// identity color throughout the setup and match UI.
enum BloomColor: Int, CaseIterable, Codable, Identifiable {
    case lime, tangerine, bubblegum, sky, grape, mint, sunny, coral

    var id: Int { rawValue }

    var name: String {
        switch self {
        case .lime: "Lime"
        case .tangerine: "Tangerine"
        case .bubblegum: "Bubblegum"
        case .sky: "Sky"
        case .grape: "Grape"
        case .mint: "Mint"
        case .sunny: "Sunny"
        case .coral: "Coral"
        }
    }

    var rgb: (Double, Double, Double) {
        switch self {
        case .lime: (0.64, 0.94, 0.18)
        case .tangerine: (1.00, 0.52, 0.10)
        case .bubblegum: (1.00, 0.38, 0.72)
        case .sky: (0.20, 0.74, 1.00)
        case .grape: (0.65, 0.40, 1.00)
        case .mint: (0.14, 0.92, 0.68)
        case .sunny: (1.00, 0.84, 0.18)
        case .coral: (1.00, 0.30, 0.34)
        }
    }

    var color: Color { Color(red: rgb.0, green: rgb.1, blue: rgb.2) }
    var uiColor: UIColor { UIColor(red: rgb.0, green: rgb.1, blue: rgb.2, alpha: 1) }
    /// A darker shade used for button lips and text on top of the color.
    var deep: Color { Color(red: rgb.0 * 0.55, green: rgb.1 * 0.55, blue: rgb.2 * 0.55) }
}

/// The playable characters (Quaternius, CC0, from chars/). All share one skeleton and
/// clip set. Raw values are saved with the crew, so existing ones must not change.
enum CharacterKind: String, CaseIterable, Codable, Identifiable {
    case ninja, classy, wizard, witch, zombieGal, zombieGuy
    case chef, elf, goblin, kimonoGal, kimonoGuy, pirateGal, pirateGuy, soldier, suit, vikingHelmet, viking

    var id: String { rawValue }

    /// Buddy was removed from the cast. Migrate that legacy saved value to Pirate Gal so
    /// an existing crew can still be opened instead of losing all of its setup data.
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = raw == "buddy" ? .pirateGal : (CharacterKind(rawValue: raw) ?? .pirateGal)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    var name: String {
        switch self {
        case .ninja: "Sand Ninja"
        case .classy: "Classy"
        case .wizard: "Wizard"
        case .witch: "Witch"
        case .zombieGal: "Zombie Gal"
        case .zombieGuy: "Zombie Guy"
        case .chef: "Chef"
        case .elf: "Elf"
        case .goblin: "Goblin"
        case .kimonoGal: "Kimono Gal"
        case .kimonoGuy: "Kimono Guy"
        case .pirateGal: "Pirate Gal"
        case .pirateGuy: "Pirate Captain"
        case .soldier: "Soldier"
        case .suit: "Business Boss"
        case .vikingHelmet: "Horned Viking"
        case .viking: "Viking"
        }
    }

    /// Model file in Models/ and portrait in the asset catalog: the raw value, capitalised.
    var asset: String { rawValue.prefix(1).uppercased() + rawValue.dropFirst() }

    /// Portrait image in the asset catalog. The color argument keeps the call site API
    /// stable even though every remaining character uses its authored outfit colors.
    func portrait(in _: BloomColor) -> String { "Character-\(asset)" }
}

struct Player: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var color: BloomColor
    var character: CharacterKind = .pirateGal
    /// Score for each finished round, in order.
    var roundScores: [Int] = []

    var total: Int { roundScores.reduce(0, +) }

    enum CodingKeys: String, CodingKey { case id, name, color, character }

    init(id: UUID = UUID(), name: String, color: BloomColor, character: CharacterKind = .pirateGal) {
        self.id = id
        self.name = name
        self.color = color
        self.character = character
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        color = try c.decode(BloomColor.self, forKey: .color)
        // Crews saved before characters existed fall back to the current lead character.
        character = try c.decodeIfPresent(CharacterKind.self, forKey: .character) ?? .pirateGal
    }
}

struct TurnResult: Equatable {
    let total: Int
    let pitch: Int
    let rhythm: Int
    let length: Int
    let isDemo: Bool

    var verdict: String {
        switch total {
        case 90...: "Uncanny. Are you the sound?"
        case 78..<90: "Seriously close!"
        case 62..<78: "Solid echo."
        case 45..<62: "We heard the ambition."
        default: "Bold. Interpretive. Wrong."
        }
    }

    var mood: MascotMood { total >= 62 ? .happy : .sad }
}

enum MascotMood: Equatable {
    case idle, listening, ready, countIn, recording, thinking, happy, sad, celebrate
}

/// Ordinal ranks with ties sharing a place: [90, 80, 80, 70] → [1, 2, 2, 4].
func competitionRanks(_ scores: [Int]) -> [Int] {
    scores.indices.map { i in scores.filter { $0 > scores[i] }.count + 1 }
}
