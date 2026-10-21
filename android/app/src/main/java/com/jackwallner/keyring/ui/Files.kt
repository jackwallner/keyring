package com.jackwallner.keyring.ui

import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import android.provider.OpenableColumns
import androidx.core.content.FileProvider
import androidx.core.graphics.scale
import com.jackwallner.keyring.AppGraph
import com.jackwallner.keyring.data.Attachment
import com.jackwallner.keyring.data.GarageStore
import java.io.ByteArrayOutputStream

/** Picked photos and files, read and scaled down like `ImageTools.jpeg` on iOS. */
object PickedFiles {
    private const val MAX_SIDE = 2_000

    /** A picked image as JPEG no wider or taller than 2,000 px; a PDF as is. */
    fun read(context: Context, uri: Uri): Pair<String, ByteArray>? {
        val name = displayName(context, uri) ?: "Document"
        val bytes = runCatching { context.contentResolver.openInputStream(uri)?.use { it.readBytes() } }.getOrNull() ?: return null
        if (GarageStore.isPDF(bytes)) return name.substringBeforeLast('.') to bytes
        return name.substringBeforeLast('.') to (jpeg(bytes) ?: return null)
    }

    fun jpeg(bytes: ByteArray): ByteArray? {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeByteArray(bytes, 0, bytes.size, bounds)
        if (bounds.outWidth <= 0) return null
        var sample = 1
        while (maxOf(bounds.outWidth, bounds.outHeight) / (sample * 2) >= MAX_SIDE) sample *= 2
        val bitmap = BitmapFactory.decodeByteArray(bytes, 0, bytes.size, BitmapFactory.Options().apply { inSampleSize = sample }) ?: return null
        val scale = MAX_SIDE.toFloat() / maxOf(bitmap.width, bitmap.height)
        val sized = if (scale < 1) bitmap.scale((bitmap.width * scale).toInt(), (bitmap.height * scale).toInt()) else bitmap
        return ByteArrayOutputStream().use { out ->
            sized.compress(Bitmap.CompressFormat.JPEG, 82, out)
            out.toByteArray()
        }
    }

    private fun displayName(context: Context, uri: Uri): String? = runCatching {
        context.contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { cursor ->
            if (cursor.moveToFirst()) cursor.getString(0) else null
        }
    }.getOrNull()

    fun text(context: Context, uri: Uri): String? =
        runCatching { context.contentResolver.openInputStream(uri)?.use { it.readBytes().toString(Charsets.UTF_8) } }.getOrNull()

    /** Opens a stored PDF in the reader's PDF app; images are shown in the app instead. */
    fun openPDF(context: Context, graph: AppGraph, attachment: Attachment) {
        val file = graph.attachmentFiles.file(attachment.file)
        val uri = FileProvider.getUriForFile(context, context.packageName + ".files", file)
        val view = Intent(Intent.ACTION_VIEW).setDataAndType(uri, "application/pdf")
            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
        try {
            context.startActivity(view)
        } catch (_: ActivityNotFoundException) {
            context.startActivity(Intent.createChooser(Intent(Intent.ACTION_SEND).setType("application/pdf").putExtra(Intent.EXTRA_STREAM, uri)
                .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION), attachment.name ?: "Document").addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        }
    }
}
