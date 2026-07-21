# API Keys Settings: design

> Superseded by `2026-07-21-settings-sidebar-providers-design.md`. This file records the narrower design that preceded the multi-provider implementation.

## Obiettivo

Rendere la sezione `API Keys` della finestra Settings leggibile e precisa, mantenendo l'aspetto nativo macOS e senza modificare il comportamento di Keychain o dei backend.

## Scope

- Modificare solo la sezione `API Keys` e il relativo stato UI in `SettingsView`.
- Lasciare invariati `General`, `Hotkeys`, `Languages`, `Translation Engine` e il footer `Done`.
- Non introdurre card custom, nuove dipendenze o un design system separato.
- Non cambiare chiavi Keychain, URL esterni o logica di selezione del backend.

## Struttura visiva

La sezione resta dentro la `Form` grouped esistente.

Ogni provider usa la stessa griglia a tre colonne:

1. nome del provider;
2. campo sicuro a larghezza stabile;
3. azione `Save`.

Una riga secondaria allineata al campo contiene le opzioni e i link del provider:

- DeepL: toggle con label visibile `Pro account` e link `Create a DeepL API key`;
- Google Cloud: link `Create a Google Cloud API key`.

Il campo usa il placeholder `Paste API key`, ma mantiene una label accessibile specifica per provider. I campi dei due provider hanno la stessa larghezza e i pulsanti condividono lo stesso allineamento.

## Stati e comportamento

- All'apertura, ogni campo riceve il valore corrente dal Keychain come oggi.
- `Save` è disabilitato finché il valore del campo non differisce da quello caricato o salvato più recentemente.
- Salvare un valore vuoto continua a eliminare la chiave.
- Il feedback è locale al provider: dopo il salvataggio, il pulsante lascia spazio a un checkmark con testo `Saved`, poi torna allo stato normale.
- Il salvataggio continua a ricaricare i backend e riallineare il backend selezionato.
- Il toggle `Pro account` mantiene la persistenza esistente in `PreferencesManager`.

## Errori e accessibilità

- La UI dichiara il salvataggio riuscito solo quando `KeychainHelper.set` o `KeychainHelper.delete` restituisce `true`. In caso contrario mostra `Could not save` per il provider interessato e mantiene `Save` abilitato.
- I `SecureField` hanno label accessibili distinte: `DeepL API key` e `Google Cloud API key`.
- Toggle, link e pulsanti restano raggiungibili da tastiera con ordine coerente dall'alto verso il basso.
- Testo e controlli usano colori e metriche di sistema, senza valori hardcoded aggiuntivi.

## Verifica

- Build Swift completata senza errori.
- Test esistenti verdi.
- Verifica visuale della finestra Settings a dimensione corrente: colonne allineate, nessun troncamento, nessun salto di layout durante il feedback `Saved`.
- Verifica tastiera e VoiceOver tramite label e ordine dei controlli.
- Verifica che una chiave modificata abiliti `Save`, che il salvataggio lo disabiliti e che un valore vuoto elimini la chiave come prima.
