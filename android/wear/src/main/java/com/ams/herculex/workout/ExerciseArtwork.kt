package com.ams.herculex.workout

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import androidx.collection.LruCache
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.wear.compose.material.Text

object ExerciseArtworkCache {
    // Memory cache for decoded exercise illustration bitmaps (capped at 20MB)
    private val memoryCache = object : LruCache<String, Bitmap>(20 * 1024 * 1024) {
        override fun sizeOf(key: String, value: Bitmap): Int = value.byteCount
    }

    fun getArtwork(context: Context, slug: String?, name: String? = null): Bitmap? {
        val candidateSlugs = mutableListOf<String>()
        if (!slug.isNullOrBlank()) {
            candidateSlugs.add(slug.lowercase().trim())
        }
        if (!name.isNullOrBlank()) {
            val normalized = name.lowercase().replace(Regex("[^a-z0-9]+"), "-").trim('-')
            if (normalized.isNotEmpty() && !candidateSlugs.contains(normalized)) {
                candidateSlugs.add(normalized)
            }
            // Candidate without parenthesis qualifiers, e.g. "Barbell Row (Overhand)" -> "barbell-row"
            val beforeParen = name.substringBefore("(").trim().lowercase().replace(Regex("[^a-z0-9]+"), "-").trim('-')
            if (beforeParen.isNotEmpty() && !candidateSlugs.contains(beforeParen)) {
                candidateSlugs.add(beforeParen)
            }
        }

        for (candidate in candidateSlugs) {
            val cached = memoryCache.get(candidate)
            if (cached != null) return cached

            val path = "images/exercises/$candidate.webp"
            try {
                context.assets.open(path).use { stream ->
                    val bitmap = BitmapFactory.decodeStream(stream)
                    if (bitmap != null) {
                        memoryCache.put(candidate, bitmap)
                        return bitmap
                    }
                }
            } catch (_: Exception) {
                // Not found under this candidate slug, try next
            }
        }
        return null
    }
}

@Composable
fun ExerciseArtwork(
    name: String,
    slug: String? = null,
    modifier: Modifier = Modifier,
    size: Dp = 38.dp,
    fallbackInitial: String = name.take(1).uppercase(),
) {
    val context = LocalContext.current
    val bitmap = remember(slug, name) {
        ExerciseArtworkCache.getArtwork(context, slug, name)
    }

    if (bitmap != null) {
        Image(
            bitmap = bitmap.asImageBitmap(),
            contentDescription = name,
            modifier = modifier
                .size(size)
                .clip(CircleShape),
            contentScale = ContentScale.Crop,
        )
    } else {
        Box(
            modifier = modifier
                .size(size)
                .background(Color(0xFF2C2C2E), shape = CircleShape),
            contentAlignment = Alignment.Center,
        ) {
            Text(
                text = fallbackInitial,
                color = Color.White,
                fontSize = 15.sp,
                fontWeight = FontWeight.Bold,
            )
        }
    }
}
