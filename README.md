# KipuBank 🏦

## Descripción del Contrato

**KipuBank** es un contrato inteligente educativo desarrollado en **Solidity** (Web3) que funciona como un sistema de **bóvedas personales** para almacenar **tokens nativos (ETH)**. El contrato aplica estrictas prácticas de seguridad, incluyendo el uso de **errores personalizados**, el patrón **Checks-Effects-Interactions** y un **guardia *nonReentrant***.

### Características Principales

1.  **Depósito de ETH:** Los usuarios pueden depositar ETH en sus bóvedas personales a través de la función `deposit()` o enviando directamente ETH al contrato.
2.  **Límite Global (`bankCap`):** Existe un límite máximo inmutable en la cantidad total de ETH que el contrato puede contener, establecido durante el despliegue.
3.  **Límite de Retiro por Transacción (`maxWithdrawPerTx`):** Los retiros están restringidos a un monto máximo por cada transacción (inmutable), incluso si el usuario tiene un saldo mayor.
4.  **Seguridad y Transparencia:** Se utilizan errores personalizados para *revertir* con claridad, y se emiten **eventos** (`Deposit`, `Withdraw`) para facilitar el seguimiento de las transacciones fuera de la cadena.
5.  **Contadores:** El contrato mantiene un registro de los depósitos totales (`depositCount`), retiros totales (`withdrawCount`) y depósitos por usuario (`depositCountPerUser`).

---

## Despliegue

### Contrato desplegado en Ethereum Sepolia

[Clic aquí para ver despliegue](https://sepolia.etherscan.io/address/0x4d9d042050a4e2c06cb53a3ba0e239ef03bd2b68#code)

### Instrucciones de Despliegue

El contrato `KipuBank` requiere dos parámetros inmutables en su **constructor** para ser desplegado:

1.  `_bankCap` (`uint256`): El límite máximo de ETH (en **wei**) que el banco puede almacenar.
2.  `_maxWithdrawPerTx` (`uint256`): El límite máximo de ETH (en **wei**) que un usuario puede retirar en una sola transacción.

### Ejemplo de Despliegue

Para desplegar el contrato, debe pasar los valores deseados para estos límites.

| Parámetro | Valor de Ejemplo (Wei) | Valor de Ejemplo (ETH) | Descripción |
| :--- | :--- | :--- | :--- |
| `_bankCap` | `100000000000000000000` | 100 ETH | Capacidad máxima del banco. |
| `_maxWithdrawPerTx` | `1000000000000000000` | 1 ETH | Límite máximo por retiro. |

**Pasos:**

1.  Compilar `KipuBank.sol` con `solc ^0.8.20`.
2.  Usar una herramienta de despliegue (Hardhat, Foundry, Remix) y proporcionar los valores iniciales para `_bankCap` y `_maxWithdrawPerTx`.

---

## Cómo Interactuar con el Contrato

Aquí se detallan las funciones clave para la interacción:

### 1. Depositar Fondos

La función es `payable`, lo que significa que debe enviársele ETH.

| Función | Tipo | Descripción | Uso |
| :--- | :--- | :--- | :--- |
| `deposit()` | `external payable` | Envía el `msg.value` (ETH) a la bóveda personal del remitente. | Llame a la función y adjunte la cantidad de ETH deseada. |
| `receive()` / `fallback()` | `external payable` | **Alternativa:** Enviar ETH directamente a la dirección del contrato sin llamar a una función. | |

> **Importante:** El depósito fallará si el monto excede el `bankCap` global.

### 2. Retirar Fondos

Esta función permite retirar el ETH de la bóveda personal, sujeto al límite por transacción.

| Función | Tipo | Parámetros | Descripción |
| :--- | :--- | :--- | :--- |
| `withdraw(uint256 amount)` | `external` | `amount`: El monto en **wei** a retirar. | Retira la cantidad especificada de la bóveda del remitente. |

> **Importante:** La transacción fallará si:
> * `amount` es 0.
> * `amount` es mayor que `maxWithdrawPerTx`.
> * `amount` es mayor que el saldo de la bóveda del usuario.

### 3. Funciones de Vista

Estas funciones son *de solo lectura* y no modifican el estado de la cadena (no cuestan gas, salvo la llamada inicial).

| Función | Tipo | Descripción |
| :--- | :--- | :--- |
| `getVaultBalance(address account)` | `external view` | Devuelve el saldo de la bóveda para una dirección específica. |
| `contractBalance()` | `external view` | Devuelve el saldo total de ETH en la dirección del contrato. |
| `totalBankBalance` | `public view` | Devuelve la suma de todos los saldos de las bóvedas. |
| `depositCount` / `withdrawCount` | `public view` | Devuelven los contadores globales de transacciones. |
| `bankCap` / `maxWithdrawPerTx` | `public view` | Devuelven los límites inmutables. |