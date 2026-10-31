package com.jackwallner.keyring.ui.theme

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.ArrowBack
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.jackwallner.keyring.model.DueStatus
import com.jackwallner.keyring.model.NumberInput

@Composable
fun Eyebrow(text: String, color: Color = Keyring.colors.secondaryInk, modifier: Modifier = Modifier) {
    Text(text.uppercase(), style = Type.caption, color = color, modifier = modifier)
}

@Composable
fun SectionHeader(title: String, modifier: Modifier = Modifier, trailing: @Composable RowScope.() -> Unit = {}) {
    Row(modifier.fillMaxWidth().padding(bottom = Space.xs), verticalAlignment = Alignment.CenterVertically) {
        Text(title, style = Type.title(20), color = Keyring.colors.ink, modifier = Modifier.weight(1f).semantics { heading() })
        trailing()
    }
}

/** A white card on paper, the app's one container. */
@Composable
fun Card(modifier: Modifier = Modifier, padding: PaddingValues = PaddingValues(Space.cardPadding), content: @Composable ColumnScope.() -> Unit) {
    val colors = Keyring.colors
    Column(
        modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(Space.radius))
            .background(colors.surface)
            .border(1.dp, colors.hairline, RoundedCornerShape(Space.radius))
            .padding(padding),
        content = content,
    )
}

@Composable
fun PrimaryButton(text: String, onClick: () -> Unit, modifier: Modifier = Modifier, enabled: Boolean = true, tag: String? = null) {
    val colors = Keyring.colors
    Button(
        onClick = onClick,
        enabled = enabled,
        shape = RoundedCornerShape(Space.smallRadius),
        colors = ButtonDefaults.buttonColors(containerColor = colors.action, contentColor = colors.onAction,
            disabledContainerColor = colors.raised, disabledContentColor = colors.faintInk),
        contentPadding = PaddingValues(horizontal = Space.md, vertical = Space.sm),
        modifier = modifier.fillMaxWidth().heightIn(min = 52.dp).let { if (tag != null) it.testTag(tag) else it },
    ) { Text(text, style = Type.headline) }
}

@Composable
fun SecondaryButton(text: String, onClick: () -> Unit, modifier: Modifier = Modifier, tag: String? = null) {
    val colors = Keyring.colors
    OutlinedButton(
        onClick = onClick,
        shape = RoundedCornerShape(Space.smallRadius),
        border = BorderStroke(1.dp, colors.hairline),
        colors = ButtonDefaults.outlinedButtonColors(containerColor = colors.surface, contentColor = colors.ink),
        modifier = modifier.fillMaxWidth().heightIn(min = 48.dp).let { if (tag != null) it.testTag(tag) else it },
    ) { Text(text, style = Type.subheadlineBold) }
}

@Composable
fun LinkButton(text: String, onClick: () -> Unit, modifier: Modifier = Modifier, color: Color = Keyring.colors.ink) {
    TextButton(onClick = onClick, modifier = modifier.heightIn(min = Space.touch)) {
        Text(text, style = Type.subheadlineBold, color = color)
    }
}

@Composable
fun TopBar(title: String, onBack: (() -> Unit)?, actions: @Composable RowScope.() -> Unit = {}) {
    Row(
        Modifier.fillMaxWidth().padding(horizontal = Space.xs, vertical = Space.xxs).heightIn(min = 56.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        if (onBack != null) {
            IconButton(onClick = onBack, modifier = Modifier.testTag("nav.back")) {
                Icon(Icons.AutoMirrored.Outlined.ArrowBack, contentDescription = "Back", tint = Keyring.colors.ink)
            }
        } else {
            Spacer(Modifier.width(Space.sm))
        }
        Text(title, style = Type.headline, color = Keyring.colors.ink, maxLines = 1, overflow = TextOverflow.Ellipsis,
            modifier = Modifier.weight(1f).semantics { heading() })
        actions()
    }
}

/** A tappable list row with an icon, a title, a subtitle and an optional trailing line. */
@Composable
fun ListRow(
    title: String,
    subtitle: String? = null,
    icon: ImageVector? = null,
    iconTint: Color = Keyring.colors.secondaryInk,
    trailing: String? = null,
    trailingColor: Color = Keyring.colors.secondaryInk,
    modifier: Modifier = Modifier,
    onClick: (() -> Unit)? = null,
) {
    val colors = Keyring.colors
    Row(
        modifier
            .fillMaxWidth()
            .heightIn(min = Space.touch)
            .let { if (onClick != null) it.clickable(role = Role.Button, onClick = onClick) else it }
            .padding(vertical = Space.rowPadding),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(Space.sm),
    ) {
        if (icon != null) {
            Box(Modifier.size(36.dp).clip(CircleShape).background(colors.raised), contentAlignment = Alignment.Center) {
                Icon(icon, contentDescription = null, tint = iconTint, modifier = Modifier.size(20.dp))
            }
        }
        Column(Modifier.weight(1f)) {
            Text(title, style = Type.subheadlineBold, color = colors.ink)
            if (!subtitle.isNullOrEmpty()) Text(subtitle, style = Type.footnote, color = colors.secondaryInk)
        }
        if (trailing != null) Text(trailing, style = Type.footnote.copy(fontWeight = androidx.compose.ui.text.font.FontWeight.SemiBold), color = trailingColor)
    }
}

@Composable
fun Divider() = HorizontalDivider(color = Keyring.colors.hairline, thickness = 1.dp)

@Composable
fun StatusDot(status: DueStatus, modifier: Modifier = Modifier) {
    Box(modifier.size(10.dp).clip(CircleShape).background(Keyring.colors.status(status)).semantics { contentDescription = status.label })
}

/** A choice chip that reads as a pill. */
@Composable
fun Chip(text: String, selected: Boolean, onClick: () -> Unit, modifier: Modifier = Modifier, tag: String? = null) {
    val colors = Keyring.colors
    Box(
        modifier
            .heightIn(min = 40.dp)
            .clip(RoundedCornerShape(50))
            .background(if (selected) colors.ink else colors.surface)
            .border(1.dp, if (selected) colors.ink else colors.hairline, RoundedCornerShape(50))
            .clickable(role = Role.Checkbox, onClick = onClick)
            .padding(horizontal = Space.md, vertical = Space.xs)
            .let { if (tag != null) it.testTag(tag) else it },
        contentAlignment = Alignment.Center,
    ) {
        Text(text, style = Type.subheadline.copy(fontWeight = androidx.compose.ui.text.font.FontWeight.Medium), color = if (selected) colors.onAction else colors.ink)
    }
}

@Composable
fun Field(
    value: String,
    onChange: (String) -> Unit,
    label: String,
    modifier: Modifier = Modifier,
    number: Boolean = false,
    tag: String? = null,
    singleLine: Boolean = true,
    supporting: String? = null,
) {
    val colors = Keyring.colors
    OutlinedTextField(
        value = value,
        onValueChange = onChange,
        label = { Text(label) },
        singleLine = singleLine,
        supportingText = supporting?.let { { Text(it) } },
        keyboardOptions = if (number) KeyboardOptions(keyboardType = KeyboardType.Decimal) else KeyboardOptions.Default,
        shape = RoundedCornerShape(Space.smallRadius),
        colors = OutlinedTextFieldDefaults.colors(
            focusedBorderColor = colors.ink, unfocusedBorderColor = colors.hairline,
            focusedContainerColor = colors.surface, unfocusedContainerColor = colors.surface,
            focusedLabelColor = colors.ink, unfocusedLabelColor = colors.secondaryInk, cursorColor = colors.ink,
        ),
        modifier = modifier.fillMaxWidth().let { if (tag != null) it.testTag(tag) else it },
    )
}

/** Parses what a person typed into a number: "45,210", "45 210" and "59,99" all work, whichever decimal mark the keyboard types. */
fun parseNumber(text: String): Double? = NumberInput.parse(text)
