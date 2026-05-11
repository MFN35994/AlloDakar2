import { initializeApp } from "https://www.gstatic.com/firebasejs/10.8.1/firebase-app.js";
import { initializeAppCheck, ReCaptchaV3Provider } from "https://www.gstatic.com/firebasejs/10.8.1/firebase-app-check.js";
import { getFirestore, collection, query, orderBy, limit, onSnapshot, doc, getDoc, updateDoc, where } from "https://www.gstatic.com/firebasejs/10.8.1/firebase-firestore.js";
import { getAuth, onAuthStateChanged, RecaptchaVerifier, signInWithPhoneNumber, signOut } from "https://www.gstatic.com/firebasejs/10.8.1/firebase-auth.js";

const firebaseConfig = {
    apiKey: "AIzaSyBI9aic0z55HA8AT31In3fbHUJy-AQ4qq4",
    appId: "1:552529206563:web:db7af28ae9b752e203c096",
    messagingSenderId: "552529206563",
    projectId: "transen-pro",
    authDomain: "transen-pro.firebaseapp.com",
    storageBucket: "transen-pro.firebasestorage.app"
};

console.log("Initializing Firebase App...");
const app = initializeApp(firebaseConfig);
const auth = getAuth(app);

// Use named database 'transen'
console.log("Connecting to Firestore (database: transen)...");
const db = getFirestore(app, "transen");

initializeAppCheck(app, {
    provider: new ReCaptchaV3Provider('6LeEVuEsAAAAAOA8c4-WJ2v8j-BCi5w1MSthhExg'),
    isTokenAutoRefreshEnabled: true
});

// Global Error Handler for Snapshots
const handleError = (error, context) => {
    console.error(`Firestore Error [${context}]:`, error);
    if (error.code === 'failed-precondition') {
        alert(`Index manquant pour ${context}. Vérifiez la console Firebase.`);
    } else if (error.code === 'permission-denied') {
        alert(`Permission refusée pour ${context}. Vérifiez vos règles de sécurité.`);
    }
};

// Auth State
let confirmationResult = null;
window.onload = () => {
    window.recaptchaVerifier = new RecaptchaVerifier(auth, 'recaptcha-container', { 'size': 'invisible' });
};

onAuthStateChanged(auth, async (user) => {
    if (user) {
        console.log("User logged in:", user.uid);
        try {
            const userDoc = await getDoc(doc(db, "users", user.uid));
            if (userDoc.exists() && userDoc.data().role === 'admin') {
                showApp(userDoc.data());
            } else {
                alert("Accès refusé. Votre compte n'a pas le rôle 'admin' dans la base 'transen'.");
                signOut(auth);
            }
        } catch (e) {
            handleError(e, "Vérification Rôle Admin");
        }
    } else {
        hideApp();
    }
});

// Login UI
document.getElementById('sendCodeBtn').onclick = async () => {
    const phone = document.getElementById('phoneNumber').value;
    try {
        confirmationResult = await signInWithPhoneNumber(auth, phone, window.recaptchaVerifier);
        document.getElementById('phone-step').style.display = "none";
        document.getElementById('otp-step').style.display = "block";
    } catch (e) { alert("Erreur SMS: " + e.message); }
};

document.getElementById('loginForm').onsubmit = async (e) => {
    e.preventDefault();
    try {
        await confirmationResult.confirm(document.getElementById('otpCode').value);
    } catch (e) { alert("Code invalide"); }
};

function showApp(userData) {
    document.getElementById('login-overlay').style.display = "none";
    document.getElementById('admin-app').style.display = "flex";
    document.getElementById('adminName').innerText = userData.name || "Admin";
    document.getElementById('currentDate').innerText = new Date().toLocaleDateString('fr-FR', { weekday: 'long', day: 'numeric', month: 'long' });
    initDashboard();
}

function hideApp() {
    document.getElementById('login-overlay').style.display = "flex";
    document.getElementById('admin-app').style.display = "none";
}

function initDashboard() {
    setupNavigation();
    syncGlobalStats();
    syncRecentActivity();
    syncLiveFeed();
    syncDrivers();
    syncUsers();
}

function setupNavigation() {
    document.querySelectorAll('#mainNav a').forEach(link => {
        link.onclick = (e) => {
            e.preventDefault();
            const section = link.getAttribute('data-section');
            document.querySelectorAll('.admin-section').forEach(s => s.style.display = 'none');
            document.getElementById(`section-${section}`).style.display = 'block';
            document.querySelectorAll('#mainNav a').forEach(l => l.classList.remove('active'));
            link.classList.add('active');
            document.getElementById('sectionTitle').innerText = link.innerText;
        };
    });
}

function syncGlobalStats() {
    console.log("Syncing Global Stats from database 'transen'...");
    
    onSnapshot(collection(db, "trips"), 
        snap => {
            console.log("TRIPS SNAPSHOT RECEIVED. Size:", snap.size);
            if (snap.size === 0) {
                console.warn("WARNING: Trips collection is EMPTY or access denied in 'transen' db.");
            }
            document.getElementById('totalTrips').innerText = snap.size;
            let rev = 0;
            snap.forEach(d => rev += (d.data().price || 0));
            document.getElementById('totalRevenue').innerText = rev.toLocaleString() + " F";
            document.getElementById('estCommissions').innerText = (rev * 0.05).toLocaleString() + " F";
        }, 
        e => {
            console.error("ERROR syncing trips:", e);
            alert("Erreur lecture 'trips' sur base 'transen': " + e.message);
        }
    );

    onSnapshot(collection(db, "users"), 
        snap => {
            console.log("USERS SNAPSHOT RECEIVED. Size:", snap.size);
            document.getElementById('totalUsers').innerText = snap.size;
            let active = 0, inactive = 0;
            snap.forEach(d => {
                const data = d.data();
                if (data.role === 'driver') {
                    if (data.status === 'active') active++; else inactive++;
                }
            });
            document.getElementById('activeDriversCount').innerText = active;
            document.getElementById('inactiveDriversCount').innerText = inactive;
        },
        e => {
            console.error("ERROR syncing users:", e);
            alert("Erreur lecture 'users' sur base 'transen': " + e.message);
        }
    );
}

function syncRecentActivity() {
    const q = query(collection(db, "trips"), orderBy("createdAt", "desc"), limit(8));
    onSnapshot(q, 
        snap => {
            const tbody = document.getElementById('activityTableBody');
            tbody.innerHTML = "";
            snap.forEach(docSnap => {
                const t = docSnap.data();
                const tr = document.createElement('tr');
                tr.innerHTML = `
                    <td>#${docSnap.id.substring(0,6)}</td>
                    <td><span class="badge blue">${t.type?.toUpperCase() || 'COURSE'}</span></td>
                    <td>${t.clientName || 'Inconnu'}</td>
                    <td>${t.price} F</td>
                    <td style="color:var(--primary); font-weight:bold">${(t.price * 0.05).toFixed(0)} F</td>
                    <td><span class="status-tag ${t.status}">${t.status.toUpperCase()}</span></td>
                `;
                tbody.appendChild(tr);
            });
        },
        e => handleError(e, "Recent Activity")
    );
}

function syncLiveFeed() {
    const q = query(collection(db, "trips"), orderBy("createdAt", "desc"), limit(50));
    onSnapshot(q, 
        snap => {
            const tbody = document.getElementById('liveTripsTableBody');
            tbody.innerHTML = "";
            snap.forEach(docSnap => {
                const t = docSnap.data();
                const date = t.createdAt?.toDate ? t.createdAt.toDate().toLocaleTimeString('fr-FR') : '--:--';
                const tr = document.createElement('tr');
                tr.innerHTML = `
                    <td>${date}</td>
                    <td>${formatServiceType(t)}</td>
                    <td><div style="font-size:0.8rem"><b>DE:</b> ${t.departure?.substring(0,25)}...<br><b>À:</b> ${t.destination?.substring(0,25)}...</div></td>
                    <td>${t.driverName || '<span style="color:gray">En recherche...</span>'}</td>
                    <td><span class="badge gold">${t.paymentMethod?.toUpperCase() || 'CASH'}</span></td>
                    <td><b>${t.price} F</b><br><small style="color:var(--primary)">Com: ${(t.price * 0.05).toFixed(0)} F</small></td>
                    <td><span class="status-tag ${t.status}">${t.status.toUpperCase()}</span></td>
                `;
                tbody.appendChild(tr);
            });
        },
        e => handleError(e, "Live Feed")
    );
}

function syncDrivers() {
    onSnapshot(query(collection(db, "users"), where("role", "==", "driver")), 
        snap => {
            const tbody = document.getElementById('driversTableBody');
            tbody.innerHTML = "";
            snap.forEach(docSnap => {
                const d = docSnap.data();
                const tr = document.createElement('tr');
                tr.innerHTML = `
                    <td><b>${d.name}</b><br><small>${d.phone}</small></td>
                    <td>${d.vehicleModel || 'N/A'}<br><small>${d.vehiclePlate || ''}</small></td>
                    <td>⭐ ${d.rating || '5.0'}</td>
                    <td>${d.walletBalance || 0} F</td>
                    <td><span class="status-tag ${d.isVerified ? 'completed' : 'pending'}">${d.isVerified ? 'OUI' : 'NON'}</span></td>
                    <td><span class="status-tag ${d.status}">${d.status?.toUpperCase() || 'INACTIF'}</span></td>
                    <td>
                        <button class="icon-btn glass" onclick="window.openDoc('${docSnap.id}', '${d.licenseImageUrl}')"><i class="fas fa-eye"></i></button>
                        <button class="icon-btn glass" onclick="window.toggleDriver('${docSnap.id}', '${d.status}')"><i class="fas fa-power-off"></i></button>
                    </td>
                `;
                tbody.appendChild(tr);
            });
        },
        e => handleError(e, "Drivers Sync")
    );
}

function syncUsers() {
    onSnapshot(query(collection(db, "users"), where("role", "==", "client"), limit(100)), 
        snap => {
            const tbody = document.getElementById('usersTableBody');
            tbody.innerHTML = "";
            snap.forEach(docSnap => {
                const u = docSnap.data();
                const tr = document.createElement('tr');
                tr.innerHTML = `
                    <td><b>${u.name}</b></td>
                    <td>${u.phone}</td>
                    <td>${u.email || '--'}</td>
                    <td>${u.referralCount || 0}</td>
                    <td>${u.bonusPoints || 0} pts</td>
                    <td><button class="icon-btn glass"><i class="fas fa-history"></i></button></td>
                `;
                tbody.appendChild(tr);
            });
        },
        e => handleError(e, "Users Sync")
    );
}

function formatServiceType(t) {
    if (t.isPool) return '<span class="badge blue">COVOITURAGE</span>';
    if (t.isYobante) return '<span class="badge gold">YOBANTÉ</span>';
    return '<span class="badge green">COURSE</span>';
}

window.toggleDriver = async (id, currentStatus) => {
    const newStatus = currentStatus === 'active' ? 'inactive' : 'active';
    await updateDoc(doc(db, "users", id), { status: newStatus });
};

window.openDoc = (userId, img) => {
    const modal = document.getElementById('docModal');
    document.getElementById('modalDocImg').src = img || 'https://via.placeholder.com/400';
    modal.style.display = "block";
    document.getElementById('approveDocBtn').onclick = () => updateDoc(doc(db, "users", userId), { isVerified: true }).then(() => modal.style.display="none");
    document.getElementById('rejectDocBtn').onclick = () => updateDoc(doc(db, "users", userId), { isVerified: false, status: 'rejected' }).then(() => modal.style.display="none");
};

document.querySelector('.close-modal').onclick = () => document.getElementById('docModal').style.display = "none";
document.getElementById('logoutBtn').onclick = () => signOut(auth);
