package com.splitfree.data

import androidx.room.Dao
import androidx.room.Database
import androidx.room.Delete
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import androidx.room.RoomDatabase
import androidx.room.Transaction
import androidx.room.TypeConverters
import androidx.room.Update
import kotlinx.coroutines.flow.Flow

/**
 * One DAO for the whole ledger. The app is small enough that splitting it per
 * entity would spread eleven near-identical files over the package for no gain.
 */
@Dao
interface LedgerDao {

    // MARK: - Participants

    @Query("SELECT * FROM participants ORDER BY isCurrentUser DESC, name COLLATE NOCASE")
    fun observeParticipants(): Flow<List<ParticipantEntity>>

    @Query("SELECT * FROM participants")
    suspend fun allParticipants(): List<ParticipantEntity>

    @Query("SELECT * FROM participants WHERE isCurrentUser = 1 LIMIT 1")
    suspend fun currentUser(): ParticipantEntity?

    @Query("SELECT * FROM participants WHERE id = :id")
    suspend fun participant(id: String): ParticipantEntity?

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsertParticipant(participant: ParticipantEntity)

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsertParticipants(participants: List<ParticipantEntity>)

    @Delete
    suspend fun deleteParticipant(participant: ParticipantEntity)

    // MARK: - Groups

    @Query("SELECT * FROM `groups` ORDER BY isPinned DESC, sortOrder ASC, createdAt DESC")
    fun observeGroups(): Flow<List<GroupEntity>>

    @Query("SELECT * FROM `groups`")
    suspend fun allGroups(): List<GroupEntity>

    @Query("SELECT * FROM `groups` WHERE id = :id")
    suspend fun group(id: String): GroupEntity?

    @Query("SELECT * FROM `groups` WHERE id = :id")
    fun observeGroup(id: String): Flow<GroupEntity?>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsertGroup(group: GroupEntity)

    @Query("DELETE FROM `groups` WHERE id = :id")
    suspend fun deleteGroup(id: String)

    @Query("SELECT * FROM group_members")
    fun observeMemberships(): Flow<List<GroupMemberEntity>>

    @Query("SELECT * FROM group_members")
    suspend fun allMemberships(): List<GroupMemberEntity>

    @Query("SELECT participantId FROM group_members WHERE groupId = :groupId")
    suspend fun memberIds(groupId: String): List<String>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun addMembers(members: List<GroupMemberEntity>)

    @Query("DELETE FROM group_members WHERE groupId = :groupId")
    suspend fun clearMembers(groupId: String)

    @Query("DELETE FROM group_members WHERE groupId = :groupId AND participantId = :participantId")
    suspend fun removeMember(groupId: String, participantId: String)

    // MARK: - Expenses

    @Query("SELECT * FROM expenses ORDER BY date DESC")
    fun observeExpenses(): Flow<List<ExpenseEntity>>

    @Query("SELECT * FROM expenses ORDER BY date DESC")
    suspend fun allExpenses(): List<ExpenseEntity>

    @Query("SELECT * FROM expenses WHERE id = :id")
    suspend fun expense(id: String): ExpenseEntity?

    @Query("SELECT * FROM expense_payers")
    fun observePayers(): Flow<List<PayerEntity>>

    @Query("SELECT * FROM expense_payers")
    suspend fun allPayers(): List<PayerEntity>

    @Query("SELECT * FROM expense_shares")
    fun observeShares(): Flow<List<ShareEntity>>

    @Query("SELECT * FROM expense_shares")
    suspend fun allShares(): List<ShareEntity>

    @Query("SELECT * FROM expense_items")
    fun observeItems(): Flow<List<LineItemEntity>>

    @Query("SELECT * FROM expense_items WHERE expenseId = :expenseId ORDER BY sortOrder")
    suspend fun items(expenseId: String): List<LineItemEntity>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsertExpense(expense: ExpenseEntity)

    @Query("DELETE FROM expenses WHERE id = :id")
    suspend fun deleteExpense(id: String)

    @Query("DELETE FROM expense_payers WHERE expenseId = :expenseId")
    suspend fun clearPayers(expenseId: String)

    @Query("DELETE FROM expense_shares WHERE expenseId = :expenseId")
    suspend fun clearShares(expenseId: String)

    @Query("DELETE FROM expense_items WHERE expenseId = :expenseId")
    suspend fun clearItems(expenseId: String)

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insertPayers(payers: List<PayerEntity>)

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insertShares(shares: List<ShareEntity>)

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insertItems(items: List<LineItemEntity>)

    /**
     * Replaces an expense's payers, shares and items in one transaction. The old
     * rows are deleted rather than mutated so a removed person can't linger with
     * a stale zero share.
     */
    @Transaction
    suspend fun saveExpense(
        expense: ExpenseEntity,
        payers: List<PayerEntity>,
        shares: List<ShareEntity>,
        items: List<LineItemEntity>,
    ) {
        upsertExpense(expense)
        clearPayers(expense.id)
        clearShares(expense.id)
        clearItems(expense.id)
        insertPayers(payers)
        insertShares(shares)
        insertItems(items)
    }

    // MARK: - Settlements

    @Query("SELECT * FROM settlements ORDER BY date DESC")
    fun observeSettlements(): Flow<List<SettlementEntity>>

    @Query("SELECT * FROM settlements ORDER BY date DESC")
    suspend fun allSettlements(): List<SettlementEntity>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsertSettlement(settlement: SettlementEntity)

    @Query("DELETE FROM settlements WHERE id = :id")
    suspend fun deleteSettlement(id: String)

    // MARK: - Activity

    @Query("SELECT * FROM activity ORDER BY createdAt DESC LIMIT 500")
    fun observeActivity(): Flow<List<ActivityEntity>>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insertActivity(entry: ActivityEntity)

    @Query("DELETE FROM activity")
    suspend fun clearActivity()

    // MARK: - Recurring rules and templates

    @Query("SELECT * FROM recurring_rules ORDER BY nextOccurrence")
    fun observeRules(): Flow<List<RecurringRuleEntity>>

    @Query("SELECT * FROM recurring_rules WHERE isActive = 1")
    suspend fun activeRules(): List<RecurringRuleEntity>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsertRule(rule: RecurringRuleEntity)

    @Update
    suspend fun updateRule(rule: RecurringRuleEntity)

    @Query("DELETE FROM recurring_rules WHERE id = :id")
    suspend fun deleteRule(id: String)

    @Query("SELECT * FROM split_templates ORDER BY lastUsedAt DESC, createdAt DESC")
    fun observeTemplates(): Flow<List<SplitTemplateEntity>>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsertTemplate(template: SplitTemplateEntity)

    @Query("DELETE FROM split_templates WHERE id = :id")
    suspend fun deleteTemplate(id: String)

    // MARK: - Sync

    @Query("SELECT * FROM sync_tombstones WHERE isPushed = 0")
    suspend fun pendingTombstones(): List<TombstoneEntity>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insertTombstone(tombstone: TombstoneEntity)

    @Update
    suspend fun updateTombstone(tombstone: TombstoneEntity)

    @Query("SELECT COUNT(*) FROM sync_tombstones WHERE entityId = :entityId")
    suspend fun tombstoneCount(entityId: String): Int

    @Query("DELETE FROM sync_tombstones WHERE isPushed = 1 AND deletedAt < :cutoff")
    suspend fun pruneTombstones(cutoff: Long)

    @Query("DELETE FROM sync_tombstones") suspend fun deleteAllTombstones()

    // MARK: - Wipe

    @Query("DELETE FROM expenses") suspend fun deleteAllExpenses()
    @Query("DELETE FROM settlements") suspend fun deleteAllSettlements()
    @Query("DELETE FROM `groups`") suspend fun deleteAllGroups()
    @Query("DELETE FROM participants") suspend fun deleteAllParticipants()
    @Query("DELETE FROM recurring_rules") suspend fun deleteAllRules()
    @Query("DELETE FROM split_templates") suspend fun deleteAllTemplates()

    @Transaction
    suspend fun eraseEverything() {
        deleteAllExpenses()
        deleteAllSettlements()
        deleteAllGroups()
        deleteAllRules()
        deleteAllTemplates()
        clearActivity()
        deleteAllParticipants()
    }
}

@Database(
    entities = [
        ParticipantEntity::class,
        GroupEntity::class,
        GroupMemberEntity::class,
        ExpenseEntity::class,
        PayerEntity::class,
        ShareEntity::class,
        LineItemEntity::class,
        SettlementEntity::class,
        ActivityEntity::class,
        RecurringRuleEntity::class,
        SplitTemplateEntity::class,
        TombstoneEntity::class,
    ],
    version = 2,
    exportSchema = true,
)
@TypeConverters(Converters::class)
abstract class SplitFreeDatabase : RoomDatabase() {
    abstract fun dao(): LedgerDao
}
