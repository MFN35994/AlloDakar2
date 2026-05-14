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

function verifySignature(req) {
    console.log("[SenePay] Headers reçus:", req.headers);
    
    // Essayer plusieurs clés possibles pour la signature
    const signature = req.headers['x-webhook-signature'] || req.headers['x-senepay-signature'] || req.headers['signature'];
    
    if (!signature) {
        console.warn("[SenePay] Aucune signature trouvée dans les headers");
        return false;
    }

    const hmac = crypto.createHmac('sha256', SENEPAY_CONFIG.apiSecret);
    const expectedSignatureHex = hmac.update(req.rawBody).digest('hex');
    
    // Recréer le HMAC pour obtenir le base64 au cas où
    const hmacB64 = crypto.createHmac('sha256', SENEPAY_CONFIG.apiSecret);
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
    const { orderReference, status, amount } = req.body;
    console.log(`[SenePay] Webhook reçu: ${orderReference} - Status: ${status} - Montant: ${amount}`);

    // VÉRIFICATION SÉCURISÉE VIA L'API SENEPAY DIRECTEMENT
    // Au lieu de se fier uniquement à la signature (qui échoue parfois selon les clés), 
    // on interroge l'API SenePay pour confirmer le statut de la transaction.
    let isVerifiedByApi = false;
    try {
        const checkResponse = await fetch(`${SENEPAY_CONFIG.baseUrl}/api/v1/checkout/sessions/${orderReference}`, {
            headers: {
                'X-Api-Key': SENEPAY_CONFIG.apiKey,
                'X-Api-Secret': SENEPAY_CONFIG.apiSecret
            }
        });
        
        if (checkResponse.ok) {
            const checkData = await checkResponse.json();
            console.log(`[SenePay] Vérification API status: ${checkData.status}`);
            
            if (checkData.status === 'Completed' || checkData.status === 'PAID' || checkData.status === 'Closed') {
                isVerifiedByApi = true;
                console.log(`[SenePay] ✅ Paiement authentifié par l'API SenePay !`);
            } else {
                console.warn(`[SenePay] ⚠️ L'API dit que le paiement n'est pas terminé (${checkData.status})`);
                return res.status(400).send("Paiement non terminé selon l'API");
            }
        }
    } catch (e) {
        console.error("❌ Erreur lors de la vérification API SenePay:", e);
    }

    // Fallback: Si l'API est injoignable ou plante, on essaie la signature
    if (!isVerifiedByApi && !verifySignature(req)) {
        console.warn("❌ [SenePay] Signature webhook invalide ET vérification API échouée");
        return res.status(401).send("Non autorisé");
    }

    if (status === 'Completed' || status === 'PAID' || isVerifiedByApi) {
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

app.post('/api/payment/create-payout', async (req, res) => {
    try {
        const response = await fetch(`${SENEPAY_CONFIG.baseUrl}/api/v1/payouts`, {
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
        res.status(500).send({ error: "Erreur serveur proxy" });
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
