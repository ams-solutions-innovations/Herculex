package com.ams.herculex.ui

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.wear.compose.material.Icon
import androidx.wear.compose.material.Text

/**
 * Samsung One UI 9 Watch Pill Design System
 */
data class OneUiPillStyle(
    val containerColor: Color,
    val badgeColor: Color,
    val contentColor: Color = Color.White,
    val secondaryColor: Color = Color(0xFFB0B8C8),
    val borderColor: Color = Color.Transparent,
    val badgeIconColor: Color? = null,
) {
    companion object {
        // Deep Royal Blue for active / primary action pills
        val RoyalBlue = OneUiPillStyle(
            containerColor = Color(0xFF1E44AA),
            badgeColor = Color(0xFF132E78),
            contentColor = Color.White,
            secondaryColor = Color(0xFFC0CCEC),
        )

        // Dark Slate Navy for general menu list items
        val SlateNavy = OneUiPillStyle(
            containerColor = Color(0xFF202636),
            badgeColor = Color(0xFF141926),
            contentColor = Color.White,
            secondaryColor = Color(0xFFA0AABF),
            borderColor = Color(0xFF323B52),
        )

        // Warm Terracotta / Copper Brown for vitals, food, alerts
        val Terracotta = OneUiPillStyle(
            containerColor = Color(0xFF5A3225),
            badgeColor = Color(0xFF3D2017),
            contentColor = Color.White,
            secondaryColor = Color(0xFFFFCCBC),
        )

        // Emerald Forest Green for active state / finished
        val EmeraldGreen = OneUiPillStyle(
            containerColor = Color(0xFF1B4D3E),
            badgeColor = Color(0xFF113329),
            contentColor = Color.White,
            secondaryColor = Color(0xFFA5D6A7),
        )

        // Deep Violet / Indigo for mindfulness / special features
        val VioletIndigo = OneUiPillStyle(
            containerColor = Color(0xFF32255C),
            badgeColor = Color(0xFF211742),
            contentColor = Color.White,
            secondaryColor = Color(0xFFD1C4E9),
        )

        // Bright Accent Blue for primary call to action
        val AccentBlue = OneUiPillStyle(
            containerColor = Color(0xFF1565C0),
            badgeColor = Color(0xFF0D47A1),
            contentColor = Color.White,
            secondaryColor = Color(0xFFBBDEFB),
        )

        // Elevated dark slate for options / secondary buttons
        val DarkSlateButton = OneUiPillStyle(
            containerColor = Color(0xFF2A2F3E),
            badgeColor = Color(0xFF1B1F2C),
            contentColor = Color.White,
            secondaryColor = Color(0xFF9098AA),
            borderColor = Color(0xFF3D4559),
        )

        // Danger / Warning pill
        val DangerTransparent = OneUiPillStyle(
            containerColor = Color.Transparent,
            badgeColor = Color(0xFF3B1C1C),
            contentColor = Color(0xFFEF5350),
            secondaryColor = Color(0xFFFF8A80),
        )
    }
}

/**
 * Standard Samsung One UI 9 Watch Stadium Pill
 *
 * Badge content, first match wins: [iconComposable], [iconVector] (an
 * [HxIcons] glyph, 22dp), then the legacy text/emoji [icon].
 */
@Composable
fun OneUiPill(
    title: String,
    modifier: Modifier = Modifier,
    subtitle: String? = null,
    subtitleColor: Color? = null,
    statValue: String? = null,
    statLabel: String? = null,
    icon: String? = null,
    iconVector: ImageVector? = null,
    iconComposable: (@Composable () -> Unit)? = null,
    style: OneUiPillStyle = OneUiPillStyle.SlateNavy,
    rightContent: (@Composable () -> Unit)? = null,
    onClick: (() -> Unit)? = null,
) {
    val hasLeading = iconComposable != null || iconVector != null || icon != null
    val hasTrailing = rightContent != null
    val isSimpleButton = !hasLeading && !hasTrailing && subtitle == null && statValue == null

    Row(
        modifier = modifier
            .fillMaxWidth()
            .heightIn(min = if (isSimpleButton) 44.dp else 52.dp)
            .background(style.containerColor, shape = CircleShape)
            .then(
                if (style.borderColor != Color.Transparent) {
                    Modifier.border(1.dp, style.borderColor, CircleShape)
                } else Modifier
            )
            .then(
                if (onClick != null) Modifier.clickable(onClick = onClick) else Modifier
            )
            .padding(
                horizontal = 14.dp,
                vertical = if (isSimpleButton) 8.dp else 10.dp,
            ),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = if (isSimpleButton) Arrangement.Center else Arrangement.Start,
    ) {
        // Left Circular Icon Badge
        if (hasLeading) {
            Box(
                modifier = Modifier
                    .size(38.dp)
                    .background(style.badgeColor, shape = CircleShape),
                contentAlignment = Alignment.Center,
            ) {
                if (iconComposable != null) {
                    iconComposable()
                } else if (iconVector != null) {
                    Icon(
                        imageVector = iconVector,
                        contentDescription = null,
                        tint = style.badgeIconColor ?: style.contentColor,
                        modifier = Modifier.size(22.dp),
                    )
                } else if (icon != null) {
                    if (icon == "▶") {
                        Box(
                            modifier = Modifier
                                .size(12.dp)
                                .offset(x = 1.dp),
                            contentAlignment = Alignment.Center
                        ) {
                            Canvas(modifier = Modifier.fillMaxSize()) {
                                val path = Path().apply {
                                    moveTo(0f, 0f)
                                    lineTo(size.width, size.height / 2f)
                                    lineTo(0f, size.height)
                                    close()
                                }
                                drawPath(path, style.contentColor)
                            }
                        }
                    } else {
                        Text(
                            text = icon,
                            fontSize = 16.sp,
                            color = style.badgeIconColor ?: style.contentColor,
                        )
                    }
                }
            }
            Spacer(Modifier.width(12.dp))
        }

        // Center Content
        Column(
            modifier = if (isSimpleButton) Modifier else Modifier.weight(1f),
            horizontalAlignment = if (isSimpleButton) Alignment.CenterHorizontally else Alignment.Start,
            verticalArrangement = Arrangement.Center,
        ) {
            Text(
                text = title,
                color = style.contentColor,
                fontWeight = FontWeight.Bold,
                fontSize = 14.sp,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
                textAlign = if (isSimpleButton) TextAlign.Center else TextAlign.Start,
            )

            if (statValue != null && statLabel != null) {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(4.dp),
                ) {
                    Text(
                        text = statValue,
                        color = style.contentColor,
                        fontWeight = FontWeight.Bold,
                        fontSize = 13.sp,
                    )
                    Text(
                        text = "|",
                        color = style.secondaryColor.copy(alpha = 0.5f),
                        fontSize = 12.sp,
                    )
                    Text(
                        text = statLabel,
                        color = style.secondaryColor,
                        fontWeight = FontWeight.Normal,
                        fontSize = 12.sp,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                }
            } else if (!subtitle.isNullOrEmpty()) {
                Text(
                    text = subtitle,
                    color = subtitleColor ?: style.secondaryColor,
                    fontWeight = FontWeight.Medium,
                    fontSize = 11.sp,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
            }
        }

        // Optional Right Action / Content
        if (hasTrailing) {
            Spacer(Modifier.width(8.dp))
            rightContent?.invoke()
        }
    }
}

/** Trailing glyph for [OneUiPill]'s `rightContent` (chevron, selected ✓, …). */
@Composable
fun OneUiPillTrailingIcon(imageVector: ImageVector, style: OneUiPillStyle) {
    Icon(
        imageVector = imageVector,
        contentDescription = null,
        tint = style.secondaryColor,
        modifier = Modifier.size(20.dp),
    )
}
