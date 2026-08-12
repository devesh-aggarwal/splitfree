import Foundation
import SwiftUI

/// Expense categories, grouped the way people actually think about a shared budget.
/// Stored by `rawValue` so renaming a title never invalidates saved data.
enum ExpenseCategory: String, CaseIterable, Codable, Identifiable, Sendable {
    // Food & drink
    case groceries, diningOut, liquor, coffee
    // Home
    case rent, mortgage, utilities, electricity, water, internet, phoneBill
    case householdSupplies, furniture, maintenance, cleaning
    // Transport
    case flight, train, bus, taxi, fuel, parking, carRental, publicTransit
    // Entertainment
    case movies, music, games, sports, events
    // Life
    case medical, insurance, education, childcare, gifts, clothing, personalCare
    case pets, charity, taxes, subscriptions
    // Travel
    case hotel, activities, souvenirs
    // Fallback
    case general

    var id: String { rawValue }

    var title: String {
        switch self {
        case .groceries: String(localized: "Groceries")
        case .diningOut: String(localized: "Dining out")
        case .liquor: String(localized: "Drinks")
        case .coffee: String(localized: "Coffee")
        case .rent: String(localized: "Rent")
        case .mortgage: String(localized: "Mortgage")
        case .utilities: String(localized: "Utilities")
        case .electricity: String(localized: "Electricity")
        case .water: String(localized: "Water")
        case .internet: String(localized: "Internet")
        case .phoneBill: String(localized: "Phone")
        case .householdSupplies: String(localized: "Household supplies")
        case .furniture: String(localized: "Furniture")
        case .maintenance: String(localized: "Maintenance")
        case .cleaning: String(localized: "Cleaning")
        case .flight: String(localized: "Flight")
        case .train: String(localized: "Train")
        case .bus: String(localized: "Bus")
        case .taxi: String(localized: "Taxi")
        case .fuel: String(localized: "Fuel")
        case .parking: String(localized: "Parking")
        case .carRental: String(localized: "Car rental")
        case .publicTransit: String(localized: "Transit")
        case .movies: String(localized: "Movies")
        case .music: String(localized: "Music")
        case .games: String(localized: "Games")
        case .sports: String(localized: "Sports")
        case .events: String(localized: "Events")
        case .medical: String(localized: "Medical")
        case .insurance: String(localized: "Insurance")
        case .education: String(localized: "Education")
        case .childcare: String(localized: "Childcare")
        case .gifts: String(localized: "Gifts")
        case .clothing: String(localized: "Clothing")
        case .personalCare: String(localized: "Personal care")
        case .pets: String(localized: "Pets")
        case .charity: String(localized: "Charity")
        case .taxes: String(localized: "Taxes")
        case .subscriptions: String(localized: "Subscriptions")
        case .hotel: String(localized: "Lodging")
        case .activities: String(localized: "Activities")
        case .souvenirs: String(localized: "Souvenirs")
        case .general: String(localized: "General")
        }
    }

    var symbol: String {
        switch self {
        case .groceries: "cart.fill"
        case .diningOut: "fork.knife"
        case .liquor: "wineglass.fill"
        case .coffee: "cup.and.saucer.fill"
        case .rent: "house.fill"
        case .mortgage: "building.columns.fill"
        case .utilities: "bolt.horizontal.fill"
        case .electricity: "bolt.fill"
        case .water: "drop.fill"
        case .internet: "wifi"
        case .phoneBill: "phone.fill"
        case .householdSupplies: "shippingbox.fill"
        case .furniture: "sofa.fill"
        case .maintenance: "wrench.and.screwdriver.fill"
        case .cleaning: "sparkles"
        case .flight: "airplane"
        case .train: "tram.fill"
        case .bus: "bus.fill"
        case .taxi: "car.fill"
        case .fuel: "fuelpump.fill"
        case .parking: "parkingsign"
        case .carRental: "car.2.fill"
        case .publicTransit: "lightrail.fill"
        case .movies: "film.fill"
        case .music: "music.note"
        case .games: "gamecontroller.fill"
        case .sports: "figure.run"
        case .events: "ticket.fill"
        case .medical: "cross.case.fill"
        case .insurance: "shield.lefthalf.filled"
        case .education: "graduationcap.fill"
        case .childcare: "figure.and.child.holdinghands"
        case .gifts: "gift.fill"
        case .clothing: "tshirt.fill"
        case .personalCare: "scissors"
        case .pets: "pawprint.fill"
        case .charity: "heart.fill"
        case .taxes: "doc.text.fill"
        case .subscriptions: "arrow.triangle.2.circlepath"
        case .hotel: "bed.double.fill"
        case .activities: "figure.hiking"
        case .souvenirs: "bag.fill"
        case .general: "list.bullet"
        }
    }

    var group: CategoryGroup {
        switch self {
        case .groceries, .diningOut, .liquor, .coffee:
            .foodAndDrink
        case .rent, .mortgage, .utilities, .electricity, .water, .internet,
             .phoneBill, .householdSupplies, .furniture, .maintenance, .cleaning:
            .home
        case .flight, .train, .bus, .taxi, .fuel, .parking, .carRental, .publicTransit:
            .transport
        case .movies, .music, .games, .sports, .events:
            .entertainment
        case .hotel, .activities, .souvenirs:
            .travel
        case .medical, .insurance, .education, .childcare, .gifts, .clothing,
             .personalCare, .pets, .charity, .taxes, .subscriptions:
            .life
        case .general:
            .other
        }
    }

    var color: Color { group.color }

    /// Best-effort category from an expense title — powers the "smart" default
    /// when someone types "Uber to airport" and never opens the category picker.
    static func suggestion(for title: String) -> ExpenseCategory? {
        let text = title.lowercased()
        guard !text.isEmpty else { return nil }
        for (keywords, category) in keywordMap {
            if keywords.contains(where: { text.contains($0) }) { return category }
        }
        return nil
    }

    private static let keywordMap: [([String], ExpenseCategory)] = [
        (["uber", "lyft", "cab", "taxi", "ola", "grab ride"], .taxi),
        (["flight", "airline", "airfare", "boarding", "delta", "united air"], .flight),
        (["hotel", "airbnb", "hostel", "motel", "lodge", "resort"], .hotel),
        (["grocer", "supermarket", "safeway", "tesco", "aldi", "kroger", "trader joe", "whole foods"], .groceries),
        (["coffee", "starbucks", "latte", "espresso", "cafe", "café"], .coffee),
        (["beer", "wine", "bar tab", "cocktail", "pub", "liquor", "brewery"], .liquor),
        (["dinner", "lunch", "brunch", "breakfast", "restaurant", "pizza", "sushi", "takeout", "doordash", "ubereats"], .diningOut),
        (["rent"], .rent),
        (["mortgage"], .mortgage),
        (["electric", "power bill"], .electricity),
        (["water bill"], .water),
        (["internet", "wifi", "broadband", "comcast", "xfinity"], .internet),
        (["phone bill", "mobile bill", "cellular", "verizon", "at&t"], .phoneBill),
        (["gas station", "petrol", "fuel", "diesel", "shell", "chevron"], .fuel),
        (["parking", "garage fee", "meter"], .parking),
        (["train", "rail", "amtrak", "metro card"], .train),
        (["bus ticket", "greyhound", "coach"], .bus),
        (["car rental", "hertz", "avis", "enterprise rent"], .carRental),
        (["movie", "cinema", "theater", "theatre"], .movies),
        (["concert", "festival", "ticket"], .events),
        (["game", "playstation", "xbox", "steam", "nintendo"], .games),
        (["gym", "yoga", "climbing", "ski pass", "lift ticket"], .sports),
        (["doctor", "pharmacy", "clinic", "hospital", "dentist", "medicine"], .medical),
        (["insurance", "premium"], .insurance),
        (["tuition", "course", "textbook", "school fee"], .education),
        (["daycare", "babysit", "nanny"], .childcare),
        (["gift", "present", "birthday"], .gifts),
        (["clothes", "clothing", "shoes", "jacket", "zara", "h&m", "uniqlo"], .clothing),
        (["haircut", "salon", "spa", "barber"], .personalCare),
        (["vet", "dog food", "cat food", "petco"], .pets),
        (["donation", "charity", "fundraiser"], .charity),
        (["tax", "irs"], .taxes),
        (["netflix", "spotify", "subscription", "hulu", "icloud", "prime"], .subscriptions),
        (["cleaning", "cleaner", "housekeep"], .cleaning),
        (["furniture", "ikea", "couch", "mattress", "desk"], .furniture),
        (["repair", "plumber", "electrician", "handyman"], .maintenance),
        (["detergent", "paper towel", "toilet paper", "soap", "supplies"], .householdSupplies),
        (["souvenir", "postcard", "magnet"], .souvenirs),
        (["tour", "museum", "excursion", "hike", "snorkel", "kayak"], .activities),
    ]
}

enum CategoryGroup: String, CaseIterable, Identifiable, Sendable {
    case foodAndDrink, home, transport, entertainment, travel, life, other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .foodAndDrink: String(localized: "Food & drink")
        case .home: String(localized: "Home")
        case .transport: String(localized: "Transport")
        case .entertainment: String(localized: "Entertainment")
        case .travel: String(localized: "Travel")
        case .life: String(localized: "Life")
        case .other: String(localized: "Other")
        }
    }

    var color: Color {
        switch self {
        case .foodAndDrink: Palette.categoryOrange
        case .home: Palette.categoryIndigo
        case .transport: Palette.categoryBlue
        case .entertainment: Palette.categoryPink
        case .travel: Palette.categoryTeal
        case .life: Palette.categoryPurple
        case .other: Palette.categoryGray
        }
    }

    var categories: [ExpenseCategory] {
        ExpenseCategory.allCases.filter { $0.group == self }
    }
}
