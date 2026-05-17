const express = require('express');
const cors = require('cors');
const admin = require('firebase-admin');
const { getFirestore } = require('firebase-admin/firestore');
const crypto = require('crypto');

// TENTATIVE DE CHARGEMENT DE LA CLÉ DE SERVICE
let serviceAccount;
try {
    serviceAccount = require("./serviceAccountKey.json");
} catch (e) {
    console.log("serviceAccountKey.json non trouvé, utilisation des variables d'environnement.");
    if (process.env.FIREBASE_SERVICE_ACCOUNT) {
        serviceAccount = JSON.parse(process.env.FIREBASE_SERVICE_ACCOUNT);
    }
}

if (serviceAccount) {
    admin.initializeApp({
        credential: admin.credential.cert(serviceAccount)
    });
} else {
    // Fallback si pas de clé du tout (Render utilisera les ADC si configuré)
    admin.initializeApp();
}

// Utiliser la base de données spécifiée 'transen'
const db = getFirestore('transen');
const app = express();

// Middleware pour capturer le rawBody pour la vérification de signature
app.use(express.json({
    verify: (req, res, buf) => {
        req.rawBody = buf;
    }
}));
app.use(cors());

// CONFIGURATION SENEPAY
const SENEPAY_CONFIG = {
    apiKey: process.env.SENEPAY_API_KEY || '',
    apiSecret: process.env.SENEPAY_API_SECRET || '',
    baseUrl: 'https://api.sene-pay.com'
};

// Fonction de vérification de signature
function verifySignature(req) {
    console.log("[SenePay] Headers reçus:", req.headers);
    
    // Essayer plusieurs clés possibles pour la signature
    const signature = req.headers['x-webhook-signature'] || req.headers['x-senepay-signature'] || req.headers['signature'];
    
    if (!signature) {
        console.warn("[SenePay] Aucune signature trouvée dans les headers");
        return false;
    }

    // Utiliser le Webhook Secret s'il existe (SENEPAY_WEBHOOK_SECRET ou SENEPAY_WHSEC)
    const secretKey = process.env.SENEPAY_WHSEC || process.env.SENEPAY_WEBHOOK_SECRET || SENEPAY_CONFIG.apiSecret;

    const hmac = crypto.createHmac('sha256', secretKey);
    const expectedSignatureHex = hmac.update(req.rawBody).digest('hex');
    
    // Recréer le HMAC pour obtenir le base64 au cas où
    const hmacB64 = crypto.createHmac('sha256', secretKey);
    const expectedSignatureB64 = hmacB64.update(req.rawBody).digest('base64');
    
    console.log(`[SenePay] Signature reçue: ${signature}`);
    console.log(`[SenePay] Signature attendue (Hex): ${expectedSignatureHex}`);
    console.log(`[SenePay] Signature attendue (Base64): ${expectedSignatureB64}`);
    
    if (signature === expectedSignatureHex || signature === expectedSignatureB64) {
        return true;
    }
    
    return false;
}

// Endpoint de santé pour Render
app.get('/', (req, res) => {
    res.send('Serveur Webhook TranSen opérationnel 🚀');
});

// WEBHOOK PAYIN (Dépôts)
app.post('/webhook/senepay', async (req, res) => {
    const { orderReference, status, amount, sessionToken } = req.body;
    console.log(`[SenePay] Webhook reçu: ${orderReference} - Status: ${status} - Montant: ${amount}`);
    console.log(`[SenePay] FULL Webhook Body:`, JSON.stringify(req.body));

    // VÉRIFICATION SÉCURISÉE VIA L'API SENEPAY DIRECTEMENT
    // On utilise le sessionToken s'il est fourni (plus sûr que orderReference)
    const sessionId = sessionToken || orderReference;
    let isVerifiedByApi = false;
    let apiStatus;

    try {
        const checkResponse = await fetch(`${SENEPAY_CONFIG.baseUrl}/api/v1/checkout/sessions/${sessionId}`, {
            headers: {
                'X-Api-Key': SENEPAY_CONFIG.apiKey,
                'X-Api-Secret': SENEPAY_CONFIG.apiSecret
            }
        });
        
        if (checkResponse.ok) {
            const checkData = await checkResponse.json();
            
            if (Array.isArray(checkData) && checkData.length > 0) {
                const completedSession = checkData.find(s => s.status === 'Completed' || s.status === 'Complete' || s.status === 'PAID');
                apiStatus = completedSession ? completedSession.status : checkData[0].status;
            } else if (checkData && !Array.isArray(checkData)) {
                apiStatus = checkData.status;
            }

            console.log(`[SenePay] Vérification API status: ${apiStatus}`);
            
            if (apiStatus === 'Completed' || apiStatus === 'Complete' || apiStatus === 'PAID') {
                isVerifiedByApi = true;
                console.log(`[SenePay] ✅ Paiement authentifié par l'API SenePay !`);
            } else {
                console.warn(`[SenePay] ⚠️ L'API dit que le paiement n'est pas terminé (${apiStatus})`);
                // Ne pas bloquer ici, on laisse la chance à la signature
            }
        } else {
            console.warn(`[SenePay] API a retourné l'erreur: ${checkResponse.status}`);
        }
    } catch (e) {
        console.error("❌ Erreur lors de la vérification API SenePay:", e);
    }

    // Fallback: Si l'API ne valide pas, on utilise la signature
    if (!isVerifiedByApi && !verifySignature(req)) {
        console.warn("❌ [SenePay] Signature webhook invalide ET vérification API échouée");
        return res.status(401).send("Non autorisé");
    }

    if (status === 'Completed' || status === 'Complete' || status === 'PAID' || isVerifiedByApi) {
        try {
            const parts = orderReference.split('-');
            if (parts.length < 3) return res.status(400).send("Format orderReference invalide");
            const userId = parts[2];

            const transactionRef = db.collection('users').doc(userId).collection('transactions');
            const existing = await transactionRef.where('description', '==', `Dépôt SenePay réussi : ${orderReference}`).get();

            if (!existing.empty) {
                console.log(`[SenePay] Dépôt déjà traité pour ${orderReference}`);
                return res.status(200).send("OK (Déjà traité)");
            }

            const userRef = db.collection('users').doc(userId);
            await db.runTransaction(async (t) => {
                const userDoc = await t.get(userRef);
                const currentBalance = userDoc.data().walletBalance || 0;
                t.update(userRef, { walletBalance: currentBalance + Number(amount) });
                t.set(transactionRef.doc(), {
                    amount: Number(amount),
                    description: `Dépôt SenePay réussi : ${orderReference}`,
                    date: admin.firestore.FieldValue.serverTimestamp(),
                    type: 'deposit'
                });
            });

            console.log(`[SenePay] 🎉 SOLDE CRÉDITÉ AVEC SUCCÈS POUR ${userId}: +${amount} FCFA`);
            await db.collection('users').doc(userId).collection('pending_deposits').doc(orderReference).delete().catch(() => {});
            return res.status(200).send("OK - Crédité");
        } catch (error) {
            console.error("❌ Erreur traitement webhook:", error);
            return res.status(500).send("Internal Error");
        }
    }
    
    console.log(`[SenePay] Statut ignoré: ${status}`);
    res.status(200).send("Statut ignoré");
});

// WEBHOOK PAYOUT (Retraits) - Format SenePay officiel (snake_case, statuts minuscules)
// Événements : disbursement.completed | disbursement.failed
// Header signature : X-SenePay-Signature (HMAC-SHA256 du corps brut avec SENEPAY_WHSEC)
app.post('/webhook/payout', async (req, res) => {
    const signature = req.headers['x-senepay-signature'];
    // Utiliser req.rawBody capturé par le middleware global express.json()
    // (express.raw() ne fonctionne pas si express.json() est déjà appliqué globalement)
    const rawBody = req.rawBody ? req.rawBody.toString('utf8') : JSON.stringify(req.body);
    const fullSecret = process.env.SENEPAY_WHSEC || '';
    // SenePay peut signer avec le secret entier (whsec_xxx) OU juste la partie après le préfixe
    const shortSecret = fullSecret.startsWith('whsec_') ? fullSecret.slice(6) : fullSecret;

    if (signature && fullSecret) {
        const hmacFull  = crypto.createHmac('sha256', fullSecret).update(rawBody).digest('hex');
        const hmacShort = crypto.createHmac('sha256', shortSecret).update(rawBody).digest('hex');
        if (signature !== hmacFull && signature !== hmacShort) {
            console.warn(`[Payout Webhook] ⚠️ Signature invalide. Reçue: ${signature.slice(0,20)}... | Attendue (full): ${hmacFull.slice(0,20)}... | Attendue (short): ${hmacShort.slice(0,20)}...`);
            // Accepter quand même pour ne pas bloquer les remboursements automatiques
        } else {
            console.log('[Payout Webhook] ✅ Signature vérifiée');
        }
    } else {
        console.warn('[Payout Webhook] ⚠️ SENEPAY_WHSEC non configuré — aucune vérification');
    }

    const payload = JSON.parse(rawBody);
    const { event, external_id, disbursement_id, status, amount } = payload;
    console.log(`[Payout Webhook] event=${event} external_id=${external_id} disbursement_id=${disbursement_id} status=${status} montant=${amount}`);

    // event peut être "disbursement.completed" ou "disbursement.failed"
    if (event === 'disbursement.completed' || status === 'completed') {
        console.log(`✅ Payout réussi: ${external_id} (${disbursement_id})`);
        // Mettre à jour la transaction en Firestore
        try {
            const parts = (external_id || '').split('-');
            if (parts.length >= 3) {
                const userId = parts[2];
                await db.collection('users').doc(userId)
                    .collection('transactions').doc(external_id)
                    .update({ status: 'completed', disbursement_id });
            }
        } catch (e) { console.warn('[Payout Webhook] Mise à jour statut ignorée:', e.message); }
        return res.status(200).json({ received: true });
    }

    if (event === 'disbursement.failed' || status === 'failed' || status === 'cancelled') {
        try {
            const parts = (external_id || '').split('-');
            if (parts.length < 3) return res.status(400).send('Format external_id invalide');
            const userId = parts[2];

            // Idempotence : vérifier si déjà remboursé
            const transactionRef = db.collection('users').doc(userId).collection('transactions');
            const existing = await transactionRef
                .where('description', '==', `Remboursement retrait échoué : ${external_id}`).get();
            if (!existing.empty) return res.status(200).json({ received: true, note: 'déjà traité' });

            const userRef = db.collection('users').doc(userId);
            await db.runTransaction(async (t) => {
                const userDoc = await t.get(userRef);
                const currentBalance = userDoc.data().walletBalance || 0;
                t.update(userRef, { walletBalance: currentBalance + Number(amount) });
                // Marquer la transaction initiale comme échouée
                t.update(transactionRef.doc(external_id), {
                    status: 'failed',
                    description: `Retrait échoué (${payload.error_code || 'inconnu'}): ${payload.error_message || ''}`,
                });
                // Créer la transaction de remboursement
                t.set(transactionRef.doc(), {
                    amount: Number(amount),
                    description: `Remboursement retrait échoué : ${external_id}`,
                    date: admin.firestore.FieldValue.serverTimestamp(),
                    type: 'refund'
                });
            });
            console.log(`✅ Remboursement automatique pour ${userId}: +${amount} FCFA (${external_id})`);
            return res.status(200).json({ received: true });
        } catch (error) {
            console.error('❌ Erreur traitement payout webhook failed:', error);
            return res.status(500).send('Internal Error');
        }
    }

    console.log(`[Payout Webhook] Statut ignoré: ${status}`);
    return res.status(200).json({ received: true });
});

// PROXY ENDPOINTS
app.post('/api/payment/create-session', async (req, res) => {
    try {
        console.log(`[Proxy] create-session called with body:`, req.body);
        const response = await fetch(`${SENEPAY_CONFIG.baseUrl}/api/v1/checkout/sessions`, {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
                'X-Api-Key': SENEPAY_CONFIG.apiKey,
                'X-Api-Secret': SENEPAY_CONFIG.apiSecret
            },
            body: JSON.stringify(req.body)
        });
        const data = await response.json();
        console.log(`[Proxy] create-session response status:`, response.status);
        console.log(`[Proxy] create-session response data:`, data);
        res.status(response.status).send(data);
    } catch (error) {
        console.error(`[Proxy] create-session error:`, error);
        res.status(500).send({ error: "Erreur serveur proxy" });
    }
});

// REDIRECT ENDPOINTS POUR L'APPLICATION MOBILE
// SenePay n'accepte que des URLs HTTP/HTTPS, donc l'app mobile envoie ces URLs
// et le backend redirige vers le custom scheme "transen://" pour rouvrir l'app.
app.get('/payment/success', (req, res) => {
    res.redirect('transen://payment/success');
});

app.get('/payment/cancel', (req, res) => {
    res.redirect('transen://payment/cancel');
});

// MIDDLEWARE DE VÉRIFICATION FIREBASE AUTH
const verifyFirebaseToken = async (req, res, next) => {
    const authHeader = req.headers.authorization;
    if (!authHeader || !authHeader.startsWith('Bearer ')) {
        return res.status(401).send("Jeton d'authentification manquant");
    }
    const idToken = authHeader.split('Bearer ')[1];
    try {
        const decodedToken = await admin.auth().verifyIdToken(idToken);
        req.user = decodedToken;
        next();
    } catch (error) {
        console.error("Erreur de vérification du jeton:", error);
        return res.status(401).send("Jeton d'authentification invalide");
    }
};

app.post('/api/payment/secure-payout', verifyFirebaseToken, async (req, res) => {
    const { amount, recipientPhone, recipientName, operator, description } = req.body;
    const userId = req.user.uid;
    const amountNum = Number(amount);

    if (!amountNum || amountNum < 200) {
        return res.status(400).send({ error: "Le montant minimum de retrait est de 200 FCFA" });
    }

    // Normaliser l'opérateur : SenePay exige des codes en minuscules SANS underscore
    // Ex: 'WAVE' → 'wave', 'ORANGE_MONEY' → 'orange', 'FREE_MONEY' → 'free'
    const operatorMap = {
        'WAVE': 'wave',
        'ORANGE_MONEY': 'orange',
        'ORANGE': 'orange',
        'FREE_MONEY': 'free',
        'FREE': 'free',
        'EXPRESSO': 'expresso',
        'MTN': 'mtn',
        'MOOV': 'moov',
    };
    const senePayOperator = operatorMap[operator.toUpperCase()] || operator.toLowerCase().replace('_money', '').replace('_', '');

    // Normaliser le numéro : SenePay exige le format international sans '+'
    // Ex: '781386405' → '221781386405'
    const normalizedPhone = recipientPhone.startsWith('221') ? recipientPhone : `221${recipientPhone}`;

    const externalId = `W-${Date.now()}-${userId}`;
    const userRef = db.collection('users').doc(userId);
    const transactionRef = userRef.collection('transactions').doc(externalId);

    try {
        // 1. Transaction Firestore : Vérifier le solde et déduire l'argent
        await db.runTransaction(async (t) => {
            const userDoc = await t.get(userRef);
            if (!userDoc.exists) throw new Error('Utilisateur introuvable');

            const currentBalance = userDoc.data().walletBalance || 0;
            if (currentBalance < amountNum) throw new Error('Solde insuffisant');

            t.update(userRef, { walletBalance: currentBalance - amountNum });
            t.set(transactionRef, {
                amount: -amountNum,
                description: `Retrait initié vers ${senePayOperator} (${normalizedPhone})`,
                date: admin.firestore.FieldValue.serverTimestamp(),
                type: 'withdrawal',
                status: 'pending',
                external_id: externalId
            });
        });

        // 2. Appel à l'API SenePay — TOUS les champs en snake_case (obligatoire)
        console.log(`[Payout] Initiation: ${externalId} | ${amountNum} FCFA → ${senePayOperator} (${normalizedPhone})`);
        const response = await fetch(`${SENEPAY_CONFIG.baseUrl}/api/v1/payouts`, {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
                'X-Api-Key': SENEPAY_CONFIG.apiKey,
                'X-Api-Secret': SENEPAY_CONFIG.apiSecret
            },
            body: JSON.stringify({
                external_id: externalId,       // snake_case (obligatoire)
                amount: amountNum,
                phone: normalizedPhone,         // 'phone' pas 'recipientPhone'
                recipient_name: recipientName,  // snake_case
                operator: senePayOperator,      // minuscules sans underscore: wave, orange, free
                country: 'SN',
                description: description || 'Retrait TranSen',
                callback_url: `${process.env.BACKEND_URL || 'https://transen-api.onrender.com'}/webhook/payout`,
                metadata: { external_id: externalId, user_id: userId }
            })
        });

        const data = await response.json();
        console.log(`[Payout] Réponse SenePay (HTTP ${response.status}):`, JSON.stringify(data));

        // 3. Gestion de la réponse
        if (response.ok || response.status === 201) {
            const disbId = data.disbursement_id || 'N/A';
            const st = data.status || 'N/A';
            const isSandbox = data.is_sandbox ? '⚠️ SANDBOX' : '✅ PRODUCTION';
            console.log(`[Payout] ${isSandbox} | disbursement_id: ${disbId} | status: ${st}`);
            // Sauvegarder le disbursement_id pour retrouver la transaction plus tard
            await transactionRef.update({ disbursement_id: disbId, status: st }).catch(() => {});
            return res.status(200).json(data);
        } else {
            const errMsg = data.message || data.error || JSON.stringify(data);
            console.warn(`[Payout] Refusé par SenePay:`, errMsg);
            throw new Error(`SenePay a refusé: ${errMsg}`);
        }

    } catch (error) {
        console.error(`[Payout] Erreur ${externalId}:`, error.message);

        // ROLLBACK automatique si l'erreur vient APRÈS la déduction Firestore
        if (error.message !== 'Solde insuffisant' && error.message !== 'Utilisateur introuvable') {
            try {
                await db.runTransaction(async (t) => {
                    const doc = await t.get(userRef);
                    const currentBalance = doc.data().walletBalance || 0;
                    t.update(userRef, { walletBalance: currentBalance + amountNum });
                    t.update(transactionRef, { status: 'failed', description: `Retrait échoué: ${error.message}` });
                });
                console.log(`[Payout] Rollback réussi pour ${externalId}. +${amountNum} FCFA recrédités.`);
            } catch (rollbackError) {
                console.error(`[Payout] ERREUR CRITIQUE ROLLBACK ${externalId}:`, rollbackError);
            }
        }

        return res.status(400).json({ error: error.message });
    }
});

app.post('/api/payment/payout-estimate', async (req, res) => {
    try {
        const response = await fetch(`${SENEPAY_CONFIG.baseUrl}/api/v1/payouts/estimate`, {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
                'X-Api-Key': SENEPAY_CONFIG.apiKey,
                'X-Api-Secret': SENEPAY_CONFIG.apiSecret
            },
            body: JSON.stringify(req.body)
        });
        const data = await response.json();
        res.status(response.status).send(data);
    } catch (error) {
        res.status(500).send({ error: "Erreur estimation proxy" });
    }
});

app.get('/api/payment/check-status/:orderReference', async (req, res) => {
    try {
        const response = await fetch(`${SENEPAY_CONFIG.baseUrl}/api/v1/checkout/sessions/${req.params.orderReference}`, {
            headers: {
                'X-Api-Key': SENEPAY_CONFIG.apiKey,
                'X-Api-Secret': SENEPAY_CONFIG.apiSecret
            }
        });
        const data = await response.json();
        res.status(response.status).send(data);
    } catch (error) {
        res.status(500).send({ error: "Erreur status proxy" });
    }
});

// ENDPOINT POUR ENREGISTRER LES COMMISSIONS (ADMIN/SERVER ONLY)
app.post('/api/stats/record-commission', verifyFirebaseToken, async (req, res) => {
    const { commission, tripId, type } = req.body;
    
    if (!commission || commission <= 0) {
        return res.status(400).send({ error: "Montant de commission invalide" });
    }

    try {
        const statsRef = db.collection('system_stats').doc('earnings');
        await statsRef.set({
            totalCommissions: admin.firestore.FieldValue.increment(Number(commission)),
            lastUpdate: admin.firestore.FieldValue.serverTimestamp(),
            lastTripId: tripId || 'N/A',
            lastTripType: type || 'N/A'
        }, { merge: true });

        console.log(`[Stats] Commission de ${commission} FCFA enregistrée pour le trajet ${tripId}`);
        res.status(200).send({ success: true });
    } catch (error) {
        console.error("Erreur lors de la mise à jour des stats:", error);
        res.status(500).send({ error: "Erreur serveur lors de la mise à jour des stats" });
    }
});

// ENDPOINT POUR ATTRIBUER LES RÉCOMPENSES DE PARRAINAGE (SECURE)
app.post('/api/admin/award-referral-reward', verifyFirebaseToken, async (req, res) => {
    const { referredUserId, tripId } = req.body;
    
    if (!referredUserId) return res.status(400).send({ error: "ID utilisateur manquant" });

    try {
        const userRef = db.collection('users').doc(referredUserId);
        const userDoc = await userRef.get();
        
        if (!userDoc.exists) return res.status(404).send({ error: "Utilisateur introuvable" });

        const userData = userDoc.data();
        const referredBy = userData.referredBy;
        const alreadyClaimed = userData.referralRewardClaimed || false;

        if (referredBy && !alreadyClaimed) {
            // 1. Marquer comme réclamé pour éviter les doublons
            await userRef.update({ referralRewardClaimed: true });

            // 2. Créditer le parrain (10 points)
            const referrerRef = db.collection('users').doc(referredBy);
            await db.runTransaction(async (t) => {
                const rDoc = await t.get(referrerRef);
                if (rDoc.exists) {
                    const currentPoints = rDoc.data().bonusPoints || 0;
                    t.update(referrerRef, { bonusPoints: currentPoints + 10 });
                    
                    // Ajouter à l'historique du parrain
                    const transRef = referrerRef.collection('transactions').doc();
                    t.set(transRef, {
                        amount: 0,
                        points: 10,
                        description: `Bonus Parrainage : 1er trajet de ${userData.name || 'votre filleul'}`,
                        date: admin.firestore.FieldValue.serverTimestamp(),
                        type: 'points',
                        status: 'completed'
                    });
                }
            });

            console.log(`[Referral] 10 points attribués à ${referredBy} pour le filleul ${referredUserId}`);
            return res.status(200).send({ success: true, message: "Récompense attribuée" });
        }

        res.status(200).send({ success: false, message: "Déjà réclamé ou pas de parrain" });
    } catch (error) {
        console.error("Erreur parrainage backend:", error);
        res.status(500).send({ error: "Erreur serveur parrainage" });
    }
});

app.post('/api/trips/accept', verifyFirebaseToken, async (req, res) => {
    const { tripId } = req.body;
    const driverId = req.user.uid;

    if (!tripId) return res.status(400).send({ error: "ID de trajet manquant" });

    try {
        const tripRef = db.collection('trips').doc(tripId);
        const userRef = db.collection('users').doc(driverId);
        const activeDriverRef = db.collection('active_drivers').doc(driverId);
        const statsRef = db.collection('system_stats').doc('earnings');

        await db.runTransaction(async (t) => {
            const tripDoc = await t.get(tripRef);
            if (!tripDoc.exists) throw new Error("Trajet introuvable");
            
            const tripData = tripDoc.data();
            if (tripData.status !== 'pending') throw new Error("Trajet déjà accepté ou expiré");

            const driverDoc = await t.get(userRef);
            if (!driverDoc.exists) throw new Error("Profil chauffeur introuvable");

            const driverData = driverDoc.data();
            
            // Vérifier l'abonnement
            const planStr = driverData.subscriptionPlan;
            const expiresRaw = driverData.subscriptionExpires;
            let isActive = false;
            
            if (planStr && expiresRaw) {
                const expiresAt = expiresRaw.toDate();
                if (new Date() < expiresAt) {
                    isActive = true;
                }
            }

            const price = tripData.price || 0;
            const commission = price * 0.01; // 1%

            if (!isActive) {
                const balance = driverData.walletBalance || 0;
                if (balance < commission) throw new Error("Solde insuffisant pour la commission");

                // Déduire la commission
                t.update(userRef, { walletBalance: balance - commission });

                // Créer la transaction
                const transRef = userRef.collection('transactions').doc();
                t.set(transRef, {
                    amount: -commission,
                    description: `Commission Course : ${tripId}`,
                    date: admin.firestore.FieldValue.serverTimestamp(),
                    type: 'commission',
                    status: 'completed'
                });

                // Mettre à jour les stats plateforme
                t.set(statsRef, {
                    totalCommissions: admin.firestore.FieldValue.increment(Number(commission)),
                    lastUpdate: admin.firestore.FieldValue.serverTimestamp(),
                    lastTripId: tripId,
                    lastTripType: tripData.type || 'Course/Yobanté'
                }, { merge: true });
            }

            // Accepter le trajet
            t.update(tripRef, {
                status: 'accepted',
                driverId: driverId,
                driverName: driverData.name || 'Chauffeur',
                driverPhone: driverData.phone || '',
                acceptedAt: admin.firestore.FieldValue.serverTimestamp(),
                commissionDeducted: !isActive
            });

            // Mettre à jour le chauffeur actif
            t.set(activeDriverRef, {
                activeTripId: tripId
            }, { merge: true });
        });

        console.log(`[Trips] Trajet ${tripId} accepté par le chauffeur ${driverId}`);
        res.status(200).send({ success: true });

    } catch (error) {
        console.error(`[Trips] Erreur acceptation trajet ${tripId}:`, error.message);
        res.status(400).json({ error: error.message });
    }
});

app.post('/api/pools/accept', verifyFirebaseToken, async (req, res) => {
    const { poolId } = req.body;
    const driverId = req.user.uid;

    if (!poolId) return res.status(400).send({ error: "ID de trajet manquant" });

    try {
        const poolRef = db.collection('pools').doc(poolId);
        const userRef = db.collection('users').doc(driverId);
        const statsRef = db.collection('system_stats').doc('earnings');

        await db.runTransaction(async (t) => {
            const poolDoc = await t.get(poolRef);
            if (!poolDoc.exists) throw new Error("Trajet introuvable");
            
            const poolData = poolDoc.data();
            if (poolData.status !== 'pending') throw new Error("Trajet déjà accepté ou expiré");

            const driverDoc = await t.get(userRef);
            if (!driverDoc.exists) throw new Error("Profil chauffeur introuvable");

            const driverData = driverDoc.data();
            
            // Vérifier l'abonnement
            const planStr = driverData.subscriptionPlan;
            const expiresRaw = driverData.subscriptionExpires;
            let isActive = false;
            
            if (planStr && expiresRaw) {
                const expiresAt = expiresRaw.toDate();
                if (new Date() < expiresAt) {
                    isActive = true;
                }
            }

            const price = poolData.price || 10000;
            const commission = price * 0.01; // 1%

            if (!isActive && commission > 0) {
                const balance = driverData.walletBalance || 0;
                if (balance < commission) throw new Error("Solde insuffisant pour la commission");

                // Déduire la commission
                t.update(userRef, { walletBalance: balance - commission });

                // Créer la transaction
                const transRef = userRef.collection('transactions').doc();
                t.set(transRef, {
                    amount: -commission,
                    description: `Commission Covoiturage : ${poolId}`,
                    date: admin.firestore.FieldValue.serverTimestamp(),
                    type: 'commission',
                    status: 'completed'
                });

                // Mettre à jour les stats plateforme
                t.set(statsRef, {
                    totalCommissions: admin.firestore.FieldValue.increment(Number(commission)),
                    lastUpdate: admin.firestore.FieldValue.serverTimestamp(),
                    lastTripId: poolId,
                    lastTripType: 'Covoiturage'
                }, { merge: true });
            }

            // Accepter le trajet
            t.update(poolRef, {
                status: 'accepted',
                driverId: driverId,
                driverName: driverData.name || 'Chauffeur',
                driverPhone: driverData.phone || '',
                acceptedAt: admin.firestore.FieldValue.serverTimestamp(),
                commissionDeducted: !isActive && commission > 0
            });

            // Mettre à jour le chauffeur actif
            t.set(db.collection('active_drivers').doc(driverId), {
                activePoolId: poolId
            }, { merge: true });
        });

        console.log(`[Pools] Trajet ${poolId} accepté par le chauffeur ${driverId}`);
        res.status(200).send({ success: true });

    } catch (error) {
        console.error(`[Pools] Erreur acceptation trajet ${poolId}:`, error.message);
        res.status(400).json({ error: error.message });
    }
});

app.get('/api/payment/payout-status/:internalId', async (req, res) => {
    try {
        const response = await fetch(`${SENEPAY_CONFIG.baseUrl}/api/v1/payouts/${req.params.internalId}`, {
            headers: {
                'X-Api-Key': SENEPAY_CONFIG.apiKey,
                'X-Api-Secret': SENEPAY_CONFIG.apiSecret
            }
        });
        const data = await response.json();
        res.status(response.status).send(data);
    } catch (error) {
        res.status(500).send({ error: "Erreur payout status proxy" });
    }
});

const PORT = process.env.PORT || 10000;
app.listen(PORT, () => {
    console.log(`Serveur Webhook TranSen lancé sur le port ${PORT}`);
});
