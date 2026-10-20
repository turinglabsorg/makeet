package org.turinglabs.makeet

import android.content.Context
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.launch
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.time.Instant

@Composable fun AccountScreen(model: MakeetModel, state: ScreenState) {
    val context = LocalContext.current; val scope = rememberCoroutineScope()
    var busy by remember { mutableStateOf(false) }
    var profile by remember { mutableStateOf(false) }; var deleting by remember { mutableStateOf(false) }
    var importing by remember { mutableStateOf(false) }; var archive by remember { mutableStateOf(false) }
    var exportScope by rememberSaveable { mutableStateOf<String?>(null) }
    var exportFailed by remember { mutableStateOf(false) }
    val exporter = rememberLauncherForActivityResult(ActivityResultContracts.CreateDocument("application/json")) { uri ->
        if(uri != null) scope.launch {
            runCatching {
                val data = model.export(exportScope ?: error("missing_export_scope"))
                withContext(Dispatchers.IO) { context.contentResolver.openOutputStream(uri)?.use { it.write(data.toByteArray()) } ?: error("export_failed") }
            }.onFailure { exportFailed = true }
            exportScope = null
        }
    }
    LazyColumn(contentPadding = PaddingValues(20.dp), verticalArrangement = Arrangement.spacedBy(20.dp)) {
        item { CardBox {
            if(state.user == null) {
                Text(t("Your private archive, synced for free."), style = MaterialTheme.typography.headlineSmall)
                Text(t("No new password. No public profile."))
                ProviderButtons(model)
                Text(t("Each account has a separate archive. Signing in never uploads local or demo data automatically."), style = MaterialTheme.typography.bodySmall)
            } else {
                Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    Avatar(state.profile, 88)
                    Text(state.profile.optString("name").ifBlank { t("Private account") }, style = MaterialTheme.typography.titleLarge)
                    Text(state.user.email)
                    OutlinedButton({ profile = true }) { Text(t("Edit profile")) }
                }
                Text(t(if(state.syncing) "Syncing" else if(state.synced) "Connected to Makeet" else "Sync is paused. Your progress stays on this device; we’ll retry when connected."))
                OutlinedButton(model::synchronize, enabled = !state.syncing) { Text(t("Sync now")) }
                if(model.localHasData()) TextButton({ importing = true }) { Text(t("Import local archive")) }
                TextButton(model::logout) { Text(t("Sign out")) }
            }
        } }
        if(state.conflicts.isNotEmpty()) item { CardBox {
            Text(t("Activity changed on multiple devices"), style = MaterialTheme.typography.titleMedium)
            Text(t("Choose which version to keep. Changes are never discarded automatically."))
            state.conflicts.forEach { remote -> Text(remote.data.optString("name", t("Activity"))); TextButton({ model.resolve(remote, true) }) { Text(t("Keep this device’s version")) }; TextButton({ model.resolve(remote, false) }) { Text(t("Use the synced version")) } }
        } }
        item { CardBox { LanguagePicker(); Text(t("All features are free, including account sync.")) } }
        item { CalendarConnections(state.user?.id ?: "local") }
        item { NotificationConnections() }
        item { CardBox {
            OutlinedButton({ archive = true }) { Text(t("Archived habits")) }
            OutlinedButton({ exportScope = state.user?.id ?: "local"; exporter.launch("makeet-${Instant.now().epochSecond}.json") }) { Text(t("Export your data")) }
            PolicyLinks()
            TextButton({ openSite(context, "support") }) { Text(t("Support")) }
            if(state.user != null) TextButton({ deleting = true }) { Text(t("Delete account"), color = MaterialTheme.colorScheme.error) }
        } }
    }
    if(profile) ProfileEditor(model, state, { profile = false })
    if(exportFailed) AlertDialog(onDismissRequest = { exportFailed = false }, title = { Text(t("Couldn’t save")) }, text = { Text(t("Your progress is retained. Check your connection or reopen this screen and try again.")) }, confirmButton = { TextButton({ exportFailed = false }) { Text(t("OK")) } })
    if(archive) FullScreen(t("Archived habits"), { archive = false }) {
        LazyColumn(contentPadding = PaddingValues(20.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
            if(state.habits.none { it.archived }) item { Text(t("No archived habits")) }
            items(state.habits.filter { it.archived }, key = { it.id }) { h -> CardBox { Text(h.name); TextButton({ model.archive(h) }) { Text(t("Restore")) }; Text(t("Archived habits keep their full history.")) } }
        }
    }
    if(importing) AlertDialog(onDismissRequest = { importing = false }, title = { Text(t("Import into this account?")) }, text = { Text(t("Copy only your real local progress into the current account. The original archive stays on this device.")) }, confirmButton = { TextButton({ model.importLocal(); importing = false }) { Text(t("Confirm import")) } }, dismissButton = { TextButton({ importing = false }) { Text(t("Cancel")) } })
    if(deleting) AlertDialog(onDismissRequest = { if(!busy) deleting = false }, title = { Text(t("Delete your Makeet account?")) }, text = { Text(t("Your account and data will be permanently deleted from the service. This action cannot be undone.")) }, confirmButton = { TextButton({ scope.launch { busy = true; if(model.deleteAccount()) deleting = false; busy = false } }, enabled = !busy) { Text(t("Delete account and data"), color = MaterialTheme.colorScheme.error) } }, dismissButton = { TextButton({ deleting = false }, enabled = !busy) { Text(t("Cancel")) } })
}

@Composable fun ProfileEditor(model: MakeetModel, state: ScreenState, close: () -> Unit) {
    var name by rememberSaveable { mutableStateOf(state.profile.optString("name")) }
    var image by rememberSaveable { mutableStateOf(state.profile.optString("image").takeUnless { it.isBlank() || it == "null" }) }
    val revision = rememberSaveable { state.profile.optLong("revision") }
    var busy by remember { mutableStateOf(false) }
    var photoFailed by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()
    val picker = rememberLauncherForActivityResult(ActivityResultContracts.PickVisualMedia()) { uri -> if(uri != null) scope.launch {
        busy = true; runCatching { model.normalizePhoto(uri) }.onSuccess { image = it }.onFailure { photoFailed = true }; busy = false
    } }
    FullScreen(t("Edit profile"), { if(!busy) close() }, actions = { TextButton({ scope.launch { busy = true; if(model.saveProfile(name.trim(), image, revision)) close(); busy = false } }, enabled = !busy && name.toByteArray().size <= 200) { Text(t("Save")) } }) {
        Column(Modifier.fillMaxSize().padding(24.dp), verticalArrangement = Arrangement.spacedBy(20.dp), horizontalAlignment = Alignment.CenterHorizontally) {
            Avatar(org.json.JSONObject().put("name", name).put("image", image), 96)
            OutlinedButton({ picker.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly)) }, enabled = !busy) { Text(t("Choose a photo")) }
            if(image != null) TextButton({ image = null }, enabled = !busy) { Text(t("Remove photo")) }
            OutlinedTextField(name, { name = it }, label = { Text(t("Your name")) }, modifier = Modifier.fillMaxWidth(), enabled = !busy, singleLine = true)
            Text(t("Your name and photo are visible only to you and saved in your account."))
        }
    }
    if(photoFailed) AlertDialog(onDismissRequest = { photoFailed = false }, title = { Text(t("Couldn’t save")) }, text = { Text(t("Your progress is retained. Check your connection or reopen this screen and try again.")) }, confirmButton = { TextButton({ photoFailed = false }) { Text(t("OK")) } })
}
