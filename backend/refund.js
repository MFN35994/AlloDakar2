const admin = require('firebase-admin');
const { getFirestore } = require('firebase-admin/firestore');

// Chargement de la clé de service (assurez-vous qu'elle est bien dans le dossier backend)
const serviceAccount = require('./serviceAccountKey.json');

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount)
});

const db = getFirestore('transen');

async function refund() {
  const userId = '5mEFZ4vTizUfGUXvFp7qzJHKhZy2';
  const amount = 500;
  const externalId = 'W-1778774591202-5mEFZ4vTizUfGUXvFp7qzJHKhZy2';
  
  try {
    const userRef = db.collection('users').doc(userId);
    const transactionRef = userRef.collection('transactions').doc(externalId);
    
    await db.runTransaction(async (t) => {
      const userDoc = await t.get(userRef);
      if (!userDoc.exists) throw new Error("Utilisateur introuvable");
      
      const currentBalance = userDoc.data().walletBalance || 0;
      t.update(userRef, { walletBalance: currentBalance + amount });
      
      t.update(transactionRef, { 
        status: 'failed', 
        description: `Retrait échoué (remboursement manuel): Wave indisponible` 
      });
      
      // Enregistrer le remboursement comme nouvelle transaction
      const refundRef = userRef.collection('transactions').doc();
      t.set(refundRef, {
        amount: amount,
        description: `Remboursement retrait échoué : ${externalId}`,
        date: admin.firestore.FieldValue.serverTimestamp(),
        type: 'refund'
      });
    });
    console.log("Remboursement effectué avec succès !");
  } catch (e) {
    console.error("Erreur:", e);
  }
}

refund();
