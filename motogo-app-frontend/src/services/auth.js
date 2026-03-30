// ===== MotoGo24 – Auth Service (Production) =====
// Handles user registration, login, logout, and session management.
// Requires supabaseClient.js to be loaded first (global `supabase` variable).
// NO mock fallbacks – production only.

/**
 * Register a new user.
 * Creates auth.users entry which triggers handle_new_user() → profiles row.
 */
async function authSignUp(email, password, metadata) {
    try {
        _ensureSupabase();
        if (!supabase) return { user: null, session: null, error: 'Supabase není připojen.' };

        var lgRaw = (metadata && metadata.license_group) || '';
        var lgArr = Array.isArray(lgRaw) ? lgRaw : (lgRaw ? [lgRaw] : []);

        var options = {
            data: {
                full_name: (metadata && metadata.full_name) || email.split('@')[0],
                phone: (metadata && metadata.phone) || '',
                license_group: lgArr
            }
        };

        var result = await supabase.auth.signUp({
            email: email,
            password: password,
            options: options
        });

        if (result.error) return { user: null, session: null, error: result.error.message };

        // Update profile with additional metadata after signup
        if (result.data.user && metadata) {
            var profileUpdate = {};
            if (metadata.phone) profileUpdate.phone = metadata.phone;
            if (metadata.license_group) {
                var lg = metadata.license_group;
                profileUpdate.license_group = Array.isArray(lg) ? lg : (lg ? [lg] : []);
            }
            if (metadata.date_of_birth) {
                // Convert Czech date format (d. m. yyyy) to ISO (yyyy-mm-dd)
                var dob = metadata.date_of_birth;
                var dm = dob.match(/(\d{1,2})\s*\.\s*(\d{1,2})\s*\.\s*(\d{4})/);
                if (dm) {
                    var dd = ('0' + dm[1]).slice(-2);
                    var mm = ('0' + dm[2]).slice(-2);
                    profileUpdate.date_of_birth = dm[3] + '-' + mm + '-' + dd;
                } else if (/^\d{4}-\d{2}-\d{2}$/.test(dob)) {
                    profileUpdate.date_of_birth = dob;
                }
            }
            if (metadata.street) profileUpdate.street = metadata.street;
            if (metadata.city) profileUpdate.city = metadata.city;
            if (metadata.zip) profileUpdate.zip = metadata.zip;
            if (metadata.country) profileUpdate.country = metadata.country;

            if (Object.keys(profileUpdate).length > 0) {
                // Small delay to allow handle_new_user trigger to create the profile row
                await new Promise(function(r){ setTimeout(r, 500); });
                await supabase
                    .from('profiles')
                    .update(profileUpdate)
                    .eq('id', result.data.user.id);
            }
        }

        return {
            user: result.data.user,
            session: result.data.session,
            error: null
        };
    } catch (e) {
        console.error('[MotoGo24] authSignUp error:', e);
        return { user: null, session: null, error: 'Chyba při registraci.' };
    }
}

/**
 * Sign in with email and password.
 */
async function authSignIn(email, password) {
    try {
        _ensureSupabase();
        if (!supabase) return { user: null, session: null, error: 'Supabase není připojen.' };

        var result = await supabase.auth.signInWithPassword({
            email: email,
            password: password
        });

        if (result.error) return { user: null, session: null, error: result.error.message };
        return { user: result.data.user, session: result.data.session, error: null };
    } catch (e) {
        console.error('[MotoGo24] authSignIn error:', e);
        return { user: null, session: null, error: 'Chyba při přihlášení.' };
    }
}

/**
 * Sign out the current user.
 */
async function authSignOut() {
    try {
        _ensureSupabase();
        if (!supabase) return { error: 'Supabase není připojen.' };

        var result = await supabase.auth.signOut();
        return { error: result.error ? result.error.message : null };
    } catch (e) {
        console.error('[MotoGo24] authSignOut error:', e);
        return { error: 'Chyba při odhlášení.' };
    }
}

/**
 * Get the current session (if logged in).
 */
async function authGetSession() {
    try {
        _ensureSupabase();
        if (!supabase) return { user: null, session: null };

        var result = await supabase.auth.getSession();
        return {
            user: result.data.session ? result.data.session.user : null,
            session: result.data.session
        };
    } catch (e) {
        console.error('[MotoGo24] authGetSession error:', e);
        return { user: null, session: null };
    }
}

/**
 * Get the current user.
 */
async function authGetUser() {
    try {
        _ensureSupabase();
        if (!supabase) return null;

        var result = await supabase.auth.getUser();
        return (result.data && result.data.user) || null;
    } catch (e) {
        console.error('[MotoGo24] authGetUser error:', e);
        return null;
    }
}

/**
 * Listen for auth state changes (login/logout).
 */
function onAuthStateChange(callback) {
    try {
        _ensureSupabase();
        if (!supabase) return { unsubscribe: function () {} };

        var result = supabase.auth.onAuthStateChange(function (event, session) {
            callback(event, session);
        });
        return result.data.subscription;
    } catch (e) {
        console.error('[MotoGo24] onAuthStateChange error:', e);
        return { unsubscribe: function () {} };
    }
}

/**
 * Reset password (send email with OTP code).
 */
async function authResetPassword(email) {
    try {
        _ensureSupabase();
        if (!supabase) return { error: 'Supabase není připojen.' };

        var result = await supabase.auth.resetPasswordForEmail(email);
        return { error: result.error ? result.error.message : null };
    } catch (e) {
        console.error('[MotoGo24] authResetPassword error:', e);
        return { error: 'Chyba při odesílání emailu pro reset hesla.' };
    }
}

/**
 * Verify OTP recovery code and get session.
 */
async function authVerifyRecoveryOtp(email, token) {
    try {
        _ensureSupabase();
        if (!supabase) return { error: 'Supabase není připojen.', session: null };

        var result = await supabase.auth.verifyOtp({
            email: email,
            token: token,
            type: 'recovery'
        });
        if (result.error) return { error: result.error.message, session: null };
        return { error: null, session: result.data.session };
    } catch (e) {
        console.error('[MotoGo24] authVerifyRecoveryOtp error:', e);
        return { error: 'Chyba při ověřování kódu.', session: null };
    }
}

/**
 * Change password for logged-in user.
 */
async function authChangePassword(newPassword) {
    try {
        _ensureSupabase();
        if (!supabase) return { error: 'Supabase není připojen.' };
        var result = await supabase.auth.updateUser({ password: newPassword });
        return { error: result.error ? result.error.message : null };
    } catch (e) {
        console.error('[MotoGo24] authChangePassword error:', e);
        return { error: 'Chyba při změně hesla.' };
    }
}
