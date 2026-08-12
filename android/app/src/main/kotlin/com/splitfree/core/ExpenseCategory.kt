package com.splitfree.core

/**
 * Expense categories, grouped the way people think about a shared budget.
 *
 * [wireName] matches the iOS app's raw values exactly, because these travel in
 * the `.splitfree` interchange file. Renaming a display title is safe; renaming
 * a wire name breaks files written by the other platform.
 */
enum class ExpenseCategory(val wireName: String, val group: CategoryGroup) {
    GROCERIES("groceries", CategoryGroup.FOOD_AND_DRINK),
    DINING_OUT("diningOut", CategoryGroup.FOOD_AND_DRINK),
    LIQUOR("liquor", CategoryGroup.FOOD_AND_DRINK),
    COFFEE("coffee", CategoryGroup.FOOD_AND_DRINK),
    RENT("rent", CategoryGroup.HOME),
    MORTGAGE("mortgage", CategoryGroup.HOME),
    UTILITIES("utilities", CategoryGroup.HOME),
    ELECTRICITY("electricity", CategoryGroup.HOME),
    WATER("water", CategoryGroup.HOME),
    INTERNET("internet", CategoryGroup.HOME),
    PHONE_BILL("phoneBill", CategoryGroup.HOME),
    HOUSEHOLD_SUPPLIES("householdSupplies", CategoryGroup.HOME),
    FURNITURE("furniture", CategoryGroup.HOME),
    MAINTENANCE("maintenance", CategoryGroup.HOME),
    CLEANING("cleaning", CategoryGroup.HOME),
    FLIGHT("flight", CategoryGroup.TRANSPORT),
    TRAIN("train", CategoryGroup.TRANSPORT),
    BUS("bus", CategoryGroup.TRANSPORT),
    TAXI("taxi", CategoryGroup.TRANSPORT),
    FUEL("fuel", CategoryGroup.TRANSPORT),
    PARKING("parking", CategoryGroup.TRANSPORT),
    CAR_RENTAL("carRental", CategoryGroup.TRANSPORT),
    PUBLIC_TRANSIT("publicTransit", CategoryGroup.TRANSPORT),
    MOVIES("movies", CategoryGroup.ENTERTAINMENT),
    MUSIC("music", CategoryGroup.ENTERTAINMENT),
    GAMES("games", CategoryGroup.ENTERTAINMENT),
    SPORTS("sports", CategoryGroup.ENTERTAINMENT),
    EVENTS("events", CategoryGroup.ENTERTAINMENT),
    MEDICAL("medical", CategoryGroup.LIFE),
    INSURANCE("insurance", CategoryGroup.LIFE),
    EDUCATION("education", CategoryGroup.LIFE),
    CHILDCARE("childcare", CategoryGroup.LIFE),
    GIFTS("gifts", CategoryGroup.LIFE),
    CLOTHING("clothing", CategoryGroup.LIFE),
    PERSONAL_CARE("personalCare", CategoryGroup.LIFE),
    PETS("pets", CategoryGroup.LIFE),
    CHARITY("charity", CategoryGroup.LIFE),
    TAXES("taxes", CategoryGroup.LIFE),
    SUBSCRIPTIONS("subscriptions", CategoryGroup.LIFE),
    HOTEL("hotel", CategoryGroup.TRAVEL),
    ACTIVITIES("activities", CategoryGroup.TRAVEL),
    SOUVENIRS("souvenirs", CategoryGroup.TRAVEL),
    GENERAL("general", CategoryGroup.OTHER),
    ;

    companion object {
        fun fromWire(value: String): ExpenseCategory =
            entries.firstOrNull { it.wireName == value } ?: GENERAL

        /**
         * Best-effort category from an expense title, so someone who types
         * "Uber to airport" and never opens the picker still gets it filed.
         */
        fun suggestion(title: String): ExpenseCategory? {
            val text = title.lowercase()
            if (text.isEmpty()) return null
            return keywordMap.firstOrNull { (keywords, _) -> keywords.any { text.contains(it) } }?.second
        }

        private val keywordMap: List<Pair<List<String>, ExpenseCategory>> = listOf(
            listOf("uber", "lyft", "cab", "taxi", "ola", "grab ride") to TAXI,
            listOf("flight", "airline", "airfare", "boarding", "delta", "united air") to FLIGHT,
            listOf("hotel", "airbnb", "hostel", "motel", "lodge", "resort") to HOTEL,
            listOf("grocer", "supermarket", "safeway", "tesco", "aldi", "kroger", "trader joe", "whole foods") to GROCERIES,
            listOf("coffee", "starbucks", "latte", "espresso", "cafe", "café") to COFFEE,
            listOf("beer", "wine", "bar tab", "cocktail", "pub", "liquor", "brewery") to LIQUOR,
            listOf("dinner", "lunch", "brunch", "breakfast", "restaurant", "pizza", "sushi", "takeout", "doordash", "ubereats") to DINING_OUT,
            listOf("rent") to RENT,
            listOf("mortgage") to MORTGAGE,
            listOf("electric", "power bill") to ELECTRICITY,
            listOf("water bill") to WATER,
            listOf("internet", "wifi", "broadband", "comcast", "xfinity") to INTERNET,
            listOf("phone bill", "mobile bill", "cellular", "verizon", "at&t") to PHONE_BILL,
            listOf("gas station", "petrol", "fuel", "diesel", "shell", "chevron") to FUEL,
            listOf("parking", "garage fee", "meter") to PARKING,
            listOf("train", "rail", "amtrak", "metro card") to TRAIN,
            listOf("bus ticket", "greyhound", "coach") to BUS,
            listOf("car rental", "hertz", "avis", "enterprise rent") to CAR_RENTAL,
            listOf("movie", "cinema", "theater", "theatre") to MOVIES,
            listOf("concert", "festival", "ticket") to EVENTS,
            listOf("game", "playstation", "xbox", "steam", "nintendo") to GAMES,
            listOf("gym", "yoga", "climbing", "ski pass", "lift ticket") to SPORTS,
            listOf("doctor", "pharmacy", "clinic", "hospital", "dentist", "medicine") to MEDICAL,
            listOf("insurance", "premium") to INSURANCE,
            listOf("tuition", "course", "textbook", "school fee") to EDUCATION,
            listOf("daycare", "babysit", "nanny") to CHILDCARE,
            listOf("gift", "present", "birthday") to GIFTS,
            listOf("clothes", "clothing", "shoes", "jacket", "zara", "h&m", "uniqlo") to CLOTHING,
            listOf("haircut", "salon", "spa", "barber") to PERSONAL_CARE,
            listOf("vet", "dog food", "cat food", "petco") to PETS,
            listOf("donation", "charity", "fundraiser") to CHARITY,
            listOf("tax", "irs") to TAXES,
            listOf("netflix", "spotify", "subscription", "hulu", "icloud", "prime") to SUBSCRIPTIONS,
            listOf("cleaning", "cleaner", "housekeep") to CLEANING,
            listOf("furniture", "ikea", "couch", "mattress", "desk") to FURNITURE,
            listOf("repair", "plumber", "electrician", "handyman") to MAINTENANCE,
            listOf("detergent", "paper towel", "toilet paper", "soap", "supplies") to HOUSEHOLD_SUPPLIES,
            listOf("souvenir", "postcard", "magnet") to SOUVENIRS,
            listOf("tour", "museum", "excursion", "hike", "snorkel", "kayak") to ACTIVITIES,
        )
    }
}

enum class CategoryGroup {
    FOOD_AND_DRINK, HOME, TRANSPORT, ENTERTAINMENT, TRAVEL, LIFE, OTHER;

    val categories: List<ExpenseCategory>
        get() = ExpenseCategory.entries.filter { it.group == this }
}
