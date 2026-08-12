package com.splitfree.ui.components

import androidx.compose.animation.animateColorAsState
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material3.Icon
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.splitfree.core.Money
import com.splitfree.data.ParticipantEntity
import com.splitfree.ui.theme.Metrics
import com.splitfree.ui.theme.MoneyType
import com.splitfree.ui.theme.splitColors

/** A person's avatar: coloured initials, with an optional selection ring. */
@Composable
fun Avatar(
    participant: ParticipantEntity,
    size: Dp = Metrics.avatarMedium,
    showsRing: Boolean = false,
    dimmed: Boolean = false,
) {
    val colors = splitColors
    val background = colors.avatarColor(participant.colorIndex)
    Box(
        modifier = Modifier
            .size(size)
            .clip(CircleShape)
            .background(if (dimmed) background.copy(alpha = 0.35f) else background)
            .then(
                if (showsRing) Modifier.border(2.5.dp, colors.accent, CircleShape) else Modifier
            ),
        contentAlignment = Alignment.Center,
    ) {
        Text(
            text = participant.initials,
            color = Color.White.copy(alpha = if (dimmed) 0.7f else 1f),
            fontSize = (size.value * 0.38f).sp,
            fontWeight = FontWeight.SemiBold,
        )
    }
}

/** Overlapping avatars with a "+N" cap: a group row's at-a-glance roster. */
@Composable
fun AvatarStack(
    participants: List<ParticipantEntity>,
    size: Dp = Metrics.avatarSmall,
    maxVisible: Int = 4,
) {
    val colors = splitColors
    val visible = participants.take(maxVisible)
    val overflow = (participants.size - maxVisible).coerceAtLeast(0)

    Row(horizontalArrangement = Arrangement.spacedBy((-size.value * 0.32f).dp)) {
        visible.forEach { person ->
            Box(modifier = Modifier.border(2.dp, colors.surface, CircleShape)) {
                Avatar(person, size)
            }
        }
        if (overflow > 0) {
            Box(
                modifier = Modifier
                    .size(size)
                    .border(2.dp, colors.surface, CircleShape)
                    .clip(CircleShape)
                    .background(colors.surfaceSunken),
                contentAlignment = Alignment.Center,
            ) {
                Text(
                    "+$overflow",
                    color = colors.secondaryText,
                    fontSize = (size.value * 0.34f).sp,
                    fontWeight = FontWeight.SemiBold,
                )
            }
        }
    }
}

/** The app's standard card. One radius, one border, used everywhere. */
@Composable
fun SplitCard(
    modifier: Modifier = Modifier,
    padding: PaddingValues = PaddingValues(Metrics.cardPadding),
    onClick: (() -> Unit)? = null,
    content: @Composable ColumnScope.() -> Unit,
) {
    val colors = splitColors
    Surface(
        modifier = modifier
            .fillMaxWidth()
            .then(if (onClick != null) Modifier.clickable(onClick = onClick) else Modifier),
        shape = RoundedCornerShape(Metrics.cardRadius),
        color = colors.surface,
        border = androidx.compose.foundation.BorderStroke(0.5.dp, colors.separator),
    ) {
        Column(modifier = Modifier.padding(padding), content = content)
    }
}

/** The rounded square that carries an expense's category. */
@Composable
fun CategoryBadge(color: Color, icon: ImageVector, size: Dp = 44.dp) {
    Box(
        modifier = Modifier
            .size(size)
            .clip(RoundedCornerShape(size * 0.3f))
            .background(color.copy(alpha = 0.14f)),
        contentAlignment = Alignment.Center,
    ) {
        Icon(icon, contentDescription = null, tint = color, modifier = Modifier.size(size * 0.5f))
    }
}

/** A balance rendered with the right color and the right words. */
@Composable
fun BalanceAmount(
    minorUnits: Long,
    currencyCode: String,
    style: androidx.compose.ui.text.TextStyle = MoneyType.row,
    settledText: String = "settled up",
) {
    val colors = splitColors
    if (minorUnits == 0L) {
        Text(settledText, color = colors.neutral, style = MaterialThemeBodyMedium())
    } else {
        val color by animateColorAsState(colors.forBalance(minorUnits), label = "balance")
        Text(
            Money(kotlin.math.abs(minorUnits), currencyCode).formatted(),
            color = color,
            style = style,
        )
    }
}

@Composable
private fun MaterialThemeBodyMedium() = androidx.compose.material3.MaterialTheme.typography.bodyMedium

/** A selectable pill: split methods, filters, date ranges. */
@Composable
fun Chip(
    label: String,
    selected: Boolean,
    modifier: Modifier = Modifier,
    icon: ImageVector? = null,
    tint: Color? = null,
    onClick: () -> Unit,
) {
    val colors = splitColors
    val accent = tint ?: colors.accent
    Surface(
        modifier = modifier.clickable(onClick = onClick),
        shape = CircleShape,
        color = if (selected) accent else colors.surfaceSunken,
    ) {
        Row(
            modifier = Modifier.padding(horizontal = 13.dp, vertical = 8.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(6.dp),
        ) {
            if (icon != null) {
                Icon(
                    icon,
                    contentDescription = null,
                    tint = if (selected) Color.White else colors.secondaryText,
                    modifier = Modifier.size(14.dp),
                )
            }
            Text(
                label,
                color = if (selected) Color.White else colors.secondaryText,
                style = androidx.compose.material3.MaterialTheme.typography.bodyMedium,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
        }
    }
}

/** An empty state with an optional call to action. */
@Composable
fun EmptyState(
    icon: ImageVector,
    title: String,
    message: String,
    actionLabel: String? = null,
    onAction: (() -> Unit)? = null,
) {
    val colors = splitColors
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = 44.dp, horizontal = Metrics.screenPadding),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        Box(
            modifier = Modifier
                .size(88.dp)
                .clip(CircleShape)
                .background(colors.accentSoft),
            contentAlignment = Alignment.Center,
        ) {
            Icon(icon, contentDescription = null, tint = colors.accent, modifier = Modifier.size(34.dp))
        }
        Text(
            title,
            style = androidx.compose.material3.MaterialTheme.typography.titleLarge,
            color = colors.primaryText,
            textAlign = TextAlign.Center,
        )
        Text(
            message,
            style = androidx.compose.material3.MaterialTheme.typography.bodyMedium,
            color = colors.secondaryText,
            textAlign = TextAlign.Center,
            modifier = Modifier.width(300.dp),
        )
        if (actionLabel != null && onAction != null) {
            Spacer(Modifier.height(2.dp))
            SecondaryButton(actionLabel, onClick = onAction)
        }
    }
}

/**
 * The filled, affirmative action on a screen. There is at most one per card:
 * two of these side by side is how a destructive choice gets made by accident.
 */
@Composable
fun PrimaryButton(
    label: String,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
    onClick: () -> Unit,
) {
    val colors = splitColors
    Surface(
        modifier = modifier.clickable(enabled = enabled, onClick = onClick),
        shape = CircleShape,
        color = if (enabled) colors.accent else colors.accent.copy(alpha = 0.35f),
    ) {
        Text(
            label,
            modifier = Modifier.padding(horizontal = 22.dp, vertical = 12.dp),
            style = androidx.compose.material3.MaterialTheme.typography.labelLarge,
            color = Color.White,
        )
    }
}

@Composable
fun SecondaryButton(label: String, modifier: Modifier = Modifier, onClick: () -> Unit) {
    val colors = splitColors
    Surface(
        modifier = modifier.clickable(onClick = onClick),
        shape = CircleShape,
        color = colors.accent.copy(alpha = 0.12f),
    ) {
        Text(
            label,
            modifier = Modifier.padding(horizontal = 14.dp, vertical = 9.dp),
            color = colors.accent,
            fontWeight = FontWeight.SemiBold,
            style = androidx.compose.material3.MaterialTheme.typography.bodyMedium,
        )
    }
}

/** A subtle badge for states worth calling out without alarming anyone. */
@Composable
fun InfoBanner(text: String, icon: ImageVector, tint: Color? = null) {
    val colors = splitColors
    val accent = tint ?: colors.categoryBlue
    Surface(
        shape = RoundedCornerShape(Metrics.chipRadius),
        color = accent.copy(alpha = 0.09f),
        modifier = Modifier.fillMaxWidth(),
    ) {
        Row(
            modifier = Modifier.padding(12.dp),
            horizontalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            Icon(icon, contentDescription = null, tint = accent, modifier = Modifier.size(16.dp))
            Text(
                text,
                style = androidx.compose.material3.MaterialTheme.typography.bodySmall,
                color = colors.secondaryText,
            )
        }
    }
}

/**
 * The persistent "does this add up?" strip used by every screen that
 * distributes a total. Green when balanced, red when not.
 */
@Composable
fun RemainderBanner(remainder: Long, currencyCode: String) {
    val colors = splitColors
    val balanced = remainder == 0L
    val message = when {
        balanced -> "Everything adds up"
        remainder > 0 -> "${Money(remainder, currencyCode).formatted()} left to assign"
        else -> "${Money(-remainder, currencyCode).formatted()} too much assigned"
    }
    Surface(
        shape = RoundedCornerShape(Metrics.chipRadius),
        color = if (balanced) colors.positiveSoft else colors.negativeSoft,
        modifier = Modifier.fillMaxWidth(),
    ) {
        Row(
            modifier = Modifier.padding(12.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            Icon(
                Icons.Filled.Check,
                contentDescription = null,
                tint = if (balanced) colors.positive else colors.negative,
                modifier = Modifier.size(16.dp),
            )
            Text(
                message,
                color = if (balanced) colors.positive else colors.negative,
                fontWeight = FontWeight.SemiBold,
                style = androidx.compose.material3.MaterialTheme.typography.bodyMedium,
            )
        }
    }
}

/** Section heading with an optional trailing action. */
@Composable
fun SectionHeader(
    title: String,
    subtitle: String? = null,
    trailing: @Composable (() -> Unit)? = null,
) {
    val colors = splitColors
    Row(
        modifier = Modifier.fillMaxWidth(),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(modifier = Modifier.weight(1f)) {
            Text(
                title,
                style = androidx.compose.material3.MaterialTheme.typography.titleMedium,
                color = colors.primaryText,
            )
            if (subtitle != null) {
                Text(
                    subtitle,
                    style = androidx.compose.material3.MaterialTheme.typography.bodySmall,
                    color = colors.secondaryText,
                )
            }
        }
        trailing?.invoke()
    }
}

/** Small uppercase label used above figures. */
@Composable
fun Overline(text: String, modifier: Modifier = Modifier) {
    Text(
        text.uppercase(),
        modifier = modifier,
        style = androidx.compose.material3.MaterialTheme.typography.labelSmall,
        color = splitColors.tertiaryText,
    )
}
