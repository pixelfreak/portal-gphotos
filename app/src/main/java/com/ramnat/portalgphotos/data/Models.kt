package com.ramnat.portalgphotos.data

import java.io.File

/** A media item the user picked, as returned by the Picker API's mediaItems.list. */
data class PickedItem(
    val id: String,
    val type: String,      // "PHOTO" | "VIDEO"
    val baseUrl: String,
    val mimeType: String,
    val filename: String,
    val width: Int,
    val height: Int,
    val createTime: String,  // RFC3339, e.g. "2024-06-15T10:30:00Z"; may be empty
)

/** A downloaded media item stored on disk and played in the slideshow. */
data class CachedItem(
    val id: String,
    val type: String,
    val file: File,
    val mimeType: String,
    val width: Int,
    val height: Int,
    val createTime: String = "",
) {
    val isVideo: Boolean get() = type == "VIDEO"

    // 0 when the picker gave us no dimensions.
    val aspectRatio: Float get() = if (width > 0 && height > 0) width.toFloat() / height else 0f
}
