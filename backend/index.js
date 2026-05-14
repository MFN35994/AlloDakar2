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

// WEBHOOK PAYOUT (Retraits)
app.post('/webhook/payout', async (req, res) => {
    if (!verifySignature(req)) {
        console.warn("[SenePay] Signature payout webhook invalide");
        return res.status(401).send("Signature invalide");
    }

    const payload = req.body.data || req.body;
    const { externalId, status, amount, internalId } = payload;
    console.log(`[SenePay] Payout Webhook reçu: ${externalId} - Status: ${status}`);

    if (status === 'Completed') {
        console.log(`✅ Payout réussi: ${externalId}`);
        return res.status(200).send("OK - Payout terminé");
    }

    if (status === 'Failed' || status === 'Cancelled' || status === 'REJECTED') {
        try {
            const parts = externalId.split('-');
            if (parts.length < 3) return res.status(400).send("Format externalId invalide");
            const userId = parts[2];

            const transactionRef = db.collection('users').doc(userId).collection('transactions');
            const existing = await transactionRef.where('description', '==', `Remboursement retrait échoué : ${internalId}`).get();

            if (!existing.empty) return res.status(200).send("OK (Déjà remboursé)");

            const userRef = db.collection('users').doc(userId);
            await db.runTransaction(async (t) => {
                const userDoc = await t.get(userRef);
                const currentBalance = userDoc.data().walletBalance || 0;
                t.update(userRef, { walletBalance: currentBalance + Number(amount) });
                t.set(transactionRef.doc(), {
                    amount: Number(amount),
                    description: `Remboursement retrait échoué : ${internalId}`,
                    date: admin.firestore.FieldValue.serverTimestamp(),
                    type: 'refund'
                });
            });
            return res.status(200).send("OK - Remboursé");
        } catch (error) {
            console.error("❌ Erreur traitement payout webhook:", error);
            return res.status(500).send("Internal Error");
        }
    }
    res.status(200).send("Statut ignoré");
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

    if (!amountNum || amountNum < 500) {
        return res.status(400).send({ error: "Le montant minimum de retrait est de 500 FCFA" });
    }

    const externalId = `W-${Date.now()}-${userId}`;
    const userRef = db.collection('users').doc(userId);
    const transactionRef = userRef.collection('transactions').doc(externalId);

    try {
        // 1. Transaction Firestore : Vérifier le solde et déduire l'argent
        await db.runTransaction(async (t) => {
            const userDoc = await t.get(userRef);
            if (!userDoc.exists) throw new Error("Utilisateur introuvable");
            
            const currentBalance = userDoc.data().walletBalance || 0;
            if (currentBalance < amountNum) {
                throw new Error("Solde insuffisant");
            }

            // Déduire le solde
            t.update(userRef, { walletBalance: currentBalance - amountNum });
            
            // Créer la transaction "en cours"
            t.set(transactionRef, {
                amount: -amountNum,
                description: `Retrait initié vers ${operator} (${recipientPhone})`,
                date: admin.firestore.FieldValue.serverTimestamp(),
                type: 'withdrawal',
                status: 'pending',
                externalId: externalId
            });
        });

        // 2. Appel à l'API SenePay
        console.log(`[Payout] Initiation du retrait ${externalId} pour ${amountNum} FCFA vers ${recipientPhone}`);
        const response = await fetch(`${SENEPAY_CONFIG.baseUrl}/api/v1/payouts`, {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
                'X-Api-Key': SENEPAY_CONFIG.apiKey,
                'X-Api-Secret': SENEPAY_CONFIG.apiSecret
            },
            body: JSON.stringify({
                externalId: externalId,
                amount: amountNum,
                recipientPhone: recipientPhone,
                recipientName: recipientName,
                operator: operator,
                country: 'SN',
                description: description || 'Retrait TranSen'
            })
        });

        const data = await response.json();
        
        // 3. Gestion de la réponse synchrone de SenePay
        if (response.ok || response.status === 201) {
            console.log(`[Payout] Retrait ${externalId} accepté par SenePay.`);
            // Le webhook de SenePay confirmera le statut définitif plus tard
            return res.status(200).send(data);
        } else {
            console.warn(`[Payout] Retrait ${externalId} refusé par SenePay:`, data);
            throw new Error(`SenePay a refusé la demande: ${data.message || 'Erreur inconnue'}`);
        }

    } catch (error) {
        console.error(`[Payout] Erreur lors du retrait ${externalId}:`, error.message);
        
        // ROLLBACK : Si l'erreur survient APRES la transaction (donc SenePay a refusé), on rembourse
        if (error.message !== "Solde insuffisant" && error.message !== "Utilisateur introuvable") {
            try {
                await db.runTransaction(async (t) => {
                    const doc = await t.get(userRef);
                    const currentBalance = doc.data().walletBalance || 0;
                    t.update(userRef, { walletBalance: currentBalance + amountNum });
                    t.update(transactionRef, { 
                        status: 'failed', 
                        description: `Retrait échoué: ${error.message}` 
                    });
                });
                console.log(`[Payout] Rollback réussi pour ${externalId}. Solde remboursé.`);
            } catch (rollbackError) {
                console.error(`[Payout] ERREUR CRITIQUE DE ROLLBACK pour ${externalId}:`, rollbackError);
            }
        }

        return res.status(400).send({ error: error.message });
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
