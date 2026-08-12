package com.splitfree

import android.app.Application
import android.content.Context
import androidx.room.Room
import com.splitfree.core.BalanceEngine
import com.splitfree.core.CategoryGroup
import com.splitfree.core.ExpenseCategory
import com.splitfree.data.LedgerRepository
import com.splitfree.data.Settings
import com.splitfree.data.SettingsStore
import com.splitfree.data.SplitFreeDatabase
import com.splitfree.ui.theme.AppearanceSetting
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.DirectionsWalk
import androidx.compose.material.icons.filled.AccountBalance
import androidx.compose.material.icons.filled.Bolt
import androidx.compose.material.icons.filled.Brush
import androidx.compose.material.icons.filled.Build
import androidx.compose.material.icons.filled.CardGiftcard
import androidx.compose.material.icons.filled.Checkroom
import androidx.compose.material.icons.filled.ChildCare
import androidx.compose.material.icons.filled.CleaningServices
import androidx.compose.material.icons.filled.Coffee
import androidx.compose.material.icons.filled.ContentCut
import androidx.compose.material.icons.filled.CreditCard
import androidx.compose.material.icons.filled.DirectionsBus
import androidx.compose.material.icons.filled.DirectionsCar
import androidx.compose.material.icons.filled.DirectionsSubway
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.filled.Flight
import androidx.compose.material.icons.filled.Hotel
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.Kitchen
import androidx.compose.material.icons.filled.LocalBar
import androidx.compose.material.icons.filled.LocalGasStation
import androidx.compose.material.icons.filled.LocalGroceryStore
import androidx.compose.material.icons.filled.LocalHospital
import androidx.compose.material.icons.filled.LocalParking
import androidx.compose.material.icons.filled.Movie
import androidx.compose.material.icons.filled.MusicNote
import androidx.compose.material.icons.filled.Pets
import androidx.compose.material.icons.filled.Phone
import androidx.compose.material.icons.filled.Restaurant
import androidx.compose.material.icons.filled.School
import androidx.compose.material.icons.filled.Security
import androidx.compose.material.icons.filled.ShoppingBag
import androidx.compose.material.icons.filled.SportsEsports
import androidx.compose.material.icons.filled.Subscriptions
import androidx.compose.material.icons.filled.Train
import androidx.compose.material.icons.filled.Description
import androidx.compose.material.icons.filled.Wifi
import androidx.compose.material.icons.filled.WaterDrop
import androidx.compose.material.icons.filled.Weekend
import androidx.compose.material.icons.filled.ConfirmationNumber
import androidx.compose.material.icons.filled.Inventory2
import androidx.compose.material.icons.automirrored.filled.List
import androidx.compose.ui.graphics.vector.ImageVector

/** Wires the database, repository and settings together. */
class SplitFreeApp : Application() {
    lateinit var container: AppContainer
        private set

    override fun onCreate() {
        super.onCreate()
        container = AppContainer(this)
    }
}

class AppContainer(context: Context) {
    private val database: SplitFreeDatabase = Room.databaseBuilder(
        context,
        SplitFreeDatabase::class.java,
        "splitfree.db",
    )
        // Version 2 only adds sync bookkeeping columns and a tombstone table.
        // Nothing anyone typed in lives in them, so rebuilding is honest here
        // and avoids hand-writing a migration for a schema nobody has shipped.
        .fallbackToDestructiveMigration()
        .build()

    val repository = LedgerRepository(database.dao())
    val settingsStore = SettingsStore(context)
    val sync = com.splitfree.sync.SyncEngine(context, database.dao())
}

/**
 * Material icons for each category.
 *
 * The iOS app uses SF Symbols, which don't exist here, so this maps each
 * category to the nearest Material equivalent. The mapping is display-only:
 * the wire names in [ExpenseCategory] are what travels between platforms.
 */
fun ExpenseCategory.icon(): ImageVector = when (this) {
    ExpenseCategory.GROCERIES -> Icons.Filled.LocalGroceryStore
    ExpenseCategory.DINING_OUT -> Icons.Filled.Restaurant
    ExpenseCategory.LIQUOR -> Icons.Filled.LocalBar
    ExpenseCategory.COFFEE -> Icons.Filled.Coffee
    ExpenseCategory.RENT -> Icons.Filled.Home
    ExpenseCategory.MORTGAGE -> Icons.Filled.AccountBalance
    ExpenseCategory.UTILITIES -> Icons.Filled.Bolt
    ExpenseCategory.ELECTRICITY -> Icons.Filled.Bolt
    ExpenseCategory.WATER -> Icons.Filled.WaterDrop
    ExpenseCategory.INTERNET -> Icons.Filled.Wifi
    ExpenseCategory.PHONE_BILL -> Icons.Filled.Phone
    ExpenseCategory.HOUSEHOLD_SUPPLIES -> Icons.Filled.Inventory2
    ExpenseCategory.FURNITURE -> Icons.Filled.Weekend
    ExpenseCategory.MAINTENANCE -> Icons.Filled.Build
    ExpenseCategory.CLEANING -> Icons.Filled.CleaningServices
    ExpenseCategory.FLIGHT -> Icons.Filled.Flight
    ExpenseCategory.TRAIN -> Icons.Filled.Train
    ExpenseCategory.BUS -> Icons.Filled.DirectionsBus
    ExpenseCategory.TAXI -> Icons.Filled.DirectionsCar
    ExpenseCategory.FUEL -> Icons.Filled.LocalGasStation
    ExpenseCategory.PARKING -> Icons.Filled.LocalParking
    ExpenseCategory.CAR_RENTAL -> Icons.Filled.DirectionsCar
    ExpenseCategory.PUBLIC_TRANSIT -> Icons.Filled.DirectionsSubway
    ExpenseCategory.MOVIES -> Icons.Filled.Movie
    ExpenseCategory.MUSIC -> Icons.Filled.MusicNote
    ExpenseCategory.GAMES -> Icons.Filled.SportsEsports
    ExpenseCategory.SPORTS -> Icons.AutoMirrored.Filled.DirectionsWalk
    ExpenseCategory.EVENTS -> Icons.Filled.ConfirmationNumber
    ExpenseCategory.MEDICAL -> Icons.Filled.LocalHospital
    ExpenseCategory.INSURANCE -> Icons.Filled.Security
    ExpenseCategory.EDUCATION -> Icons.Filled.School
    ExpenseCategory.CHILDCARE -> Icons.Filled.ChildCare
    ExpenseCategory.GIFTS -> Icons.Filled.CardGiftcard
    ExpenseCategory.CLOTHING -> Icons.Filled.Checkroom
    ExpenseCategory.PERSONAL_CARE -> Icons.Filled.ContentCut
    ExpenseCategory.PETS -> Icons.Filled.Pets
    ExpenseCategory.CHARITY -> Icons.Filled.Favorite
    ExpenseCategory.TAXES -> Icons.Filled.Description
    ExpenseCategory.SUBSCRIPTIONS -> Icons.Filled.Subscriptions
    ExpenseCategory.HOTEL -> Icons.Filled.Hotel
    ExpenseCategory.ACTIVITIES -> Icons.Filled.Brush
    ExpenseCategory.SOUVENIRS -> Icons.Filled.ShoppingBag
    ExpenseCategory.GENERAL -> Icons.AutoMirrored.Filled.List
}

/** Display title, read from the generated string resources. */
fun ExpenseCategory.titleResName(): String = "category_" + wireName.replace(
    Regex("([A-Z])")
) { "_" + it.groupValues[1].lowercase() }

fun CategoryGroup.titleResName(): String = "category_group_" + name.lowercase()

/** Group kinds, matching the iOS `GroupKind` wire values. */
enum class GroupKind(val wireName: String, val label: String) {
    TRIP("trip", "Trip"),
    HOME("home", "Home"),
    COUPLE("couple", "Couple"),
    EVENT("event", "Event"),
    PROJECT("project", "Project"),
    OTHER("other", "Other");

    companion object {
        fun fromWire(value: String) = entries.firstOrNull { it.wireName == value } ?: OTHER
    }
}

/** Payment methods, matching the iOS `PaymentMethod` wire values. */
enum class PaymentMethod(val wireName: String, val label: String) {
    CASH("cash", "Cash"),
    BANK_TRANSFER("bankTransfer", "Bank transfer"),
    VENMO("venmo", "Venmo"),
    PAYPAL("paypal", "PayPal"),
    CASH_APP("cashApp", "Cash App"),
    UPI("upi", "UPI"),
    ZELLE("zelle", "Zelle"),
    REVOLUT("revolut", "Revolut"),
    WISE("wise", "Wise"),
    OTHER("other", "Other");

    companion object {
        fun fromWire(value: String) = entries.firstOrNull { it.wireName == value } ?: CASH
    }
}
