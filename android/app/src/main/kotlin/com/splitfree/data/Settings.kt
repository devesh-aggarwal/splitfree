package com.splitfree.data

import android.content.Context
import androidx.datastore.preferences.core.booleanPreferencesKey
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import com.splitfree.core.Currencies
import com.splitfree.ui.theme.AppearanceSetting
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map

private val Context.dataStore by preferencesDataStore(name = "splitfree_settings")

/**
 * Device-level preferences. Deliberately separate from the ledger: these
 * describe how *this* device shows the data, not the data itself, so they are
 * never part of an interchange export.
 */
data class Settings(
    val baseCurrencyCode: String = Currencies.deviceDefault(),
    val hasCompletedOnboarding: Boolean = false,
    /**
     * On by default. Fewer payments is what almost everyone wants, and the
     * per-group toggle is there for anyone who'd rather see the literal history
     * of who paid for whom.
     */
    val simplifyDebtsByDefault: Boolean = true,
    val convertToBaseCurrency: Boolean = true,
    val appearance: AppearanceSetting = AppearanceSetting.SYSTEM,
    val requireBiometricUnlock: Boolean = false,
    val recentCurrencies: List<String> = emptyList(),
)

class SettingsStore(private val context: Context) {

    private object Keys {
        val baseCurrency = stringPreferencesKey("baseCurrency")
        val onboarded = booleanPreferencesKey("onboarded")
        val simplifyDefault = booleanPreferencesKey("simplifyDebtsByDefault")
        val convertToBase = booleanPreferencesKey("convertToBaseCurrency")
        val appearance = stringPreferencesKey("appearance")
        val biometric = booleanPreferencesKey("requireBiometricUnlock")
        val recentCurrencies = stringPreferencesKey("recentCurrencies")
    }

    val settings: Flow<Settings> = context.dataStore.data.map { prefs ->
        Settings(
            baseCurrencyCode = prefs[Keys.baseCurrency] ?: Currencies.deviceDefault(),
            hasCompletedOnboarding = prefs[Keys.onboarded] ?: false,
            simplifyDebtsByDefault = prefs[Keys.simplifyDefault] ?: true,
            convertToBaseCurrency = prefs[Keys.convertToBase] ?: true,
            appearance = runCatching {
                AppearanceSetting.valueOf(prefs[Keys.appearance] ?: "SYSTEM")
            }.getOrDefault(AppearanceSetting.SYSTEM),
            requireBiometricUnlock = prefs[Keys.biometric] ?: false,
            recentCurrencies = prefs[Keys.recentCurrencies]
                ?.split(",")?.filter { it.isNotBlank() } ?: emptyList(),
        )
    }

    suspend fun setBaseCurrency(code: String) =
        context.dataStore.edit { it[Keys.baseCurrency] = code }

    suspend fun setOnboarded(value: Boolean) =
        context.dataStore.edit { it[Keys.onboarded] = value }

    suspend fun setSimplifyByDefault(value: Boolean) =
        context.dataStore.edit { it[Keys.simplifyDefault] = value }

    suspend fun setConvertToBase(value: Boolean) =
        context.dataStore.edit { it[Keys.convertToBase] = value }

    suspend fun setAppearance(value: AppearanceSetting) =
        context.dataStore.edit { it[Keys.appearance] = value.name }

    suspend fun setRequireBiometric(value: Boolean) =
        context.dataStore.edit { it[Keys.biometric] = value }

    suspend fun noteCurrencyUsed(code: String) = context.dataStore.edit { prefs ->
        val existing = prefs[Keys.recentCurrencies]?.split(",")?.filter { it.isNotBlank() } ?: emptyList()
        prefs[Keys.recentCurrencies] = (listOf(code) + existing.filter { it != code }).take(6).joinToString(",")
    }
}
