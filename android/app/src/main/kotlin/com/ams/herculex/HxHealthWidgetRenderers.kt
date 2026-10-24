package com.ams.herculex

/** Shared compact layout for the daily sleep and steps home-screen widgets. */
fun HxWidgetRenderer.healthMetric(
    w: Float,
    h: Float,
    accent: Int,
    icon: HxIcon,
    caption: String,
    value: String?,
    unit: String?,
    description: String,
): HxRendered {
    val bitmap = draw(w, h) {
        card(w, h, p, accent)
        val cy = h / 2
        iconChip(icon, 30f, cy, 32f, 18f, alpha(accent, 0.15f), accent)

        val x = 56f
        val textWidth = w - x - 14f
        val blockHeight = lineHeight(label) + 2 + 22
        val top = cy - blockHeight / 2
        text(caption, x, baseline(top, label), label, maxWidth = textWidth)

        val valueStyle = grotesk(22f, accent)
        val valueTop = top + lineHeight(label) + 2
        val valueWidth = text(value ?: "—", x, baseline(valueTop, valueStyle, 22f), valueStyle,
            maxWidth = textWidth)
        val unitWidth = textWidth - valueWidth - 3
        if (unit != null && unitWidth > 0) {
            val unitStyle = manrope(11f, 400, p.secondary)
            text(unit, x + valueWidth + 3, baseline(valueTop, valueStyle, 22f), unitStyle,
                maxWidth = unitWidth)
        }
    }
    return HxRendered(bitmap, description)
}
