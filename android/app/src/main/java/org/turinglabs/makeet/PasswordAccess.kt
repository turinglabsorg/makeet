package org.turinglabs.makeet

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.launch

@Composable fun PasswordAccess(model: MakeetModel, userID: String?, close: () -> Unit, completed: () -> Unit) {
    var mode by remember { mutableStateOf(if(userID == null) "login" else "enroll") }
    var identifier by remember { mutableStateOf("") }
    var username by remember { mutableStateOf("") }
    var email by remember { mutableStateOf("") }
    var password by remember { mutableStateOf("") }
    var repeated by remember { mutableStateOf("") }
    var code by remember { mutableStateOf("") }
    var requestID by remember { mutableStateOf<String?>(null) }
    var busy by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    var saved by remember { mutableStateOf(false) }
    var existing by remember { mutableStateOf<String?>(null) }
    val scope = rememberCoroutineScope()
    LaunchedEffect(userID) {
        if(userID != null) {
            busy = true
            try { val value = model.passwordStatus(userID); if(value.optBoolean("enabled")) existing = value.getString("username") }
            catch(e: CancellationException) { throw e }
            catch(_: Exception) { error = "Check your details or code and try again. Your archive is retained." }
            finally { busy = false }
        }
    }
    fun restart(next: String) { mode = next; password = ""; repeated = ""; code = ""; requestID = null; error = null }
    val title = when(mode) { "register" -> "Create account"; "recover" -> "Recover password"; "enroll" -> "Username and password"; else -> "Sign in with password" }
    FullScreen(t(title), { if(!busy) close() }) {
        Column(Modifier.fillMaxSize().imePadding().verticalScroll(rememberScrollState()).padding(24.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
            if(saved) {
                Text(t("Credentials saved. You can use them on your other device too."))
                Button(completed) { Text(t("Done")) }
            } else if(existing != null) {
                Text(t("Username")); Text(existing!!)
                Text(t("To change your password, sign out and choose Forgot password. Your old sessions will be signed out."))
            } else {
                if(requestID == null) {
                    if(mode == "login" || mode == "recover") OutlinedTextField(identifier, { identifier = it }, label = { Text(t("Username or email")) }, singleLine = true, modifier = Modifier.fillMaxWidth(), enabled = !busy)
                    else {
                        OutlinedTextField(username, { username = it }, label = { Text(t("Username")) }, singleLine = true, modifier = Modifier.fillMaxWidth(), enabled = !busy)
                        Text(t("3–32 characters: unaccented letters, numbers, dot, hyphen or underscore."), style = MaterialTheme.typography.bodySmall)
                        OutlinedTextField(email, { email = it }, label = { Text(t("Recovery email")) }, singleLine = true, modifier = Modifier.fillMaxWidth(), enabled = !busy, keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Email))
                    }
                } else {
                    Text(t("If the request is valid, you’ll receive an email code. It expires in 15 minutes. Check spam too."))
                    OutlinedTextField(code, { code = it }, label = { Text(t("Verification code")) }, singleLine = true, modifier = Modifier.fillMaxWidth(), enabled = !busy, keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number))
                }
                if((mode != "recover" && requestID == null) || (mode == "recover" && requestID != null)) {
                    OutlinedTextField(password, { password = it }, label = { Text(t("Password")) }, singleLine = true, visualTransformation = PasswordVisualTransformation(), keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password), modifier = Modifier.fillMaxWidth(), enabled = !busy)
                    if(mode != "login") {
                        OutlinedTextField(repeated, { repeated = it }, label = { Text(t("Repeat password")) }, singleLine = true, visualTransformation = PasswordVisualTransformation(), keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password), modifier = Modifier.fillMaxWidth(), enabled = !busy)
                        Text(t("Use 15–128 characters. A phrase with spaces is welcome."), style = MaterialTheme.typography.bodySmall)
                    }
                }
                error?.let { Text(t(it), color = MaterialTheme.colorScheme.error) }
                val validPassword = password.codePointCount(0, password.length) in 15..128 && password == repeated
                val enabled = !busy && when {
                    requestID != null -> code.length == 8 && (mode != "recover" || validPassword)
                    mode == "login" -> identifier.isNotBlank() && password.isNotEmpty()
                    mode == "recover" -> identifier.isNotBlank()
                    else -> username.length >= 3 && email.contains("@") && validPassword
                }
                Button(onClick = { scope.launch {
                    busy = true; error = null
                    try {
                        val id = requestID
                        if(id != null) {
                            model.confirmPassword(id, code, if(mode == "recover") password else "", userID)
                            if(userID != null) { saved = true; password = ""; repeated = ""; code = "" }
                            else { model.passwordLogin(if(mode == "register") username else identifier, password); password = ""; repeated = ""; code = ""; completed() }
                        } else if(mode == "login") { model.passwordLogin(identifier, password); password = ""; completed() }
                        else if(mode == "recover") requestID = model.recoverPassword(identifier)
                        else requestID = model.requestPassword(username, email, password, userID)
                    } catch(e: CancellationException) { throw e }
                    catch(e: Exception) {
                        error = when((e as? APIFailure)?.status) {
                            429 -> "Too many attempts. Wait and try again."
                            503 -> "Password access is temporarily unavailable. Try again later."
                            else -> "Check your details or code and try again. Your archive is retained."
                        }
                    } finally { busy = false }
                } }, enabled = enabled, modifier = Modifier.fillMaxWidth().heightIn(min = 54.dp)) {
                    Text(t(if(requestID != null) "Confirm code" else if(mode == "login") "Sign in" else "Send code"))
                    if(busy) CircularProgressIndicator(Modifier.size(20.dp), strokeWidth = 2.dp)
                }
                if(userID == null && requestID == null) {
                    TextButton({ restart(if(mode == "register") "login" else "register") }, enabled = !busy) { Text(t(if(mode == "register") "Sign in" else "Create account")) }
                    TextButton({ restart("recover") }, enabled = !busy) { Text(t("Forgot password")) }
                }
                if(requestID != null || mode == "recover") TextButton({ restart(if(userID == null) "login" else "enroll") }, enabled = !busy) { Text(t("Start again")) }
                if(mode == "register") Text(t("Already have an account? Add credentials in Account on the device where you are signed in to keep your progress."), style = MaterialTheme.typography.bodySmall)
            }
        }
    }
}
