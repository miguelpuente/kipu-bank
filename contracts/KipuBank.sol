// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

/// @title KipuBank - Vaults personales en ETH con límites y contadores
/// @author Miguel Puente
/// @notice Contrato educativo que implementa bóvedas de ETH personales con límites de depósito global y de retiro por transacción.
/// Sigue buenas prácticas: errores personalizados, Checks-Effects-Interactions, guard contra reentrancy y manejo seguro de ETH.

contract KipuBank {

    /*/////////////////////////////////////////////////////////////
                            ERRORES PERSONALIZADOS
    /////////////////////////////////////////////////////////////*/

    /// @notice El depósito excede la capacidad total del banco
    /// @param bankCap Límite del banco (wei)
    /// @param attempted Monto intentado (wei)
    /// @param currentBankBalance Balance actual (wei)
    error BankCapExceeded(uint256 bankCap, uint256 attempted, uint256 currentBankBalance);

    /// @notice Saldo insuficiente en la bóveda para la operación
    /// @param available Balance disponible (wei)
    /// @param required Monto requerido (wei)
    error InsufficientBalance(uint256 available, uint256 required);

    /// @notice El retiro excede el límite máximo por transacción
    /// @param maxPerTx Límite permitido (wei)
    /// @param attempted Monto solicitado (wei)
    error ExceedsPerTxLimit(uint256 maxPerTx, uint256 attempted);

    /// @notice Llamada reentrante detectada
    error ReentrantCall();

    /// @notice No se permiten valores nulos (cero) para esta operación
    error ZeroValueNotAllowed();

    /// @notice Falló la transferencia de ETH
    /// @param to Dirección destino
    /// @param amount Monto (wei)
    error TransferFailed(address to, uint256 amount);


    /*/////////////////////////////////////////////////////////////
                            VARIABLES INMUTABLES
    /////////////////////////////////////////////////////////////*/

    /// @notice Límite global (inmutable) de ETH que el banco puede contener (wei)
    uint256 public immutable bankCap;

    /// @notice Límite máximo por retiro y por transacción (inmutable) (wei)
    uint256 public immutable maxWithdrawPerTx;


    /*/////////////////////////////////////////////////////////////
                            VARIABLES DE ALMACENAMIENTO (ESTADO)
    /////////////////////////////////////////////////////////////*/

    /// @notice Suma de todos los saldos almacenados en `vaults`
    uint256 public totalBankBalance;

    /// @notice Bóvedas de usuarios: mapeo de dirección a su balance en ETH (wei)
    mapping(address => uint256) private vaults;

    /// @notice Contador total de depósitos realizados
    uint256 public depositCount;

    /// @notice Contador total de retiros realizados
    uint256 public withdrawCount;

    /// @notice Contador de depósitos por usuario
    mapping(address => uint256) public depositCountPerUser;

    /// @notice Bloqueo para el modificador nonReentrant (1 = unlocked, 2 = locked)
    uint256 private _locked = 1;


    /*/////////////////////////////////////////////////////////////
                                EVENTOS
    /////////////////////////////////////////////////////////////*/

    /// @notice Emitido cuando un usuario deposita ETH en su bóveda
    /// @param account Dirección del depositante
    /// @param amount Monto depositado (en wei)
    /// @param newBalance Nuevo balance del usuario tras el depósito
    event Deposit(address indexed account, uint256 amount, uint256 newBalance);


    /// @notice Emitido cuando un usuario retira ETH de su bóveda
    /// @param account Dirección que realiza el retiro
    /// @param amount Monto retirado (en wei)
    /// @param newBalance Nuevo balance del usuario tras el retiro
    event Withdraw(address indexed account, uint256 amount, uint256 newBalance);


    /*/////////////////////////////////////////////////////////////
                                CONSTRUCTOR
    /////////////////////////////////////////////////////////////*/

    /// @notice Inicializa el límite global de depósito y el límite máximo de retiro por transacción
    /// @param _bankCap Límite máximo de ETH (en wei) que puede almacenar el contrato
    /// @param _maxWithdrawPerTx Límite por retiro y por transacción (en wei)
    constructor(uint256 _bankCap, uint256 _maxWithdrawPerTx) {
        if (_bankCap == 0 || _maxWithdrawPerTx == 0) revert ZeroValueNotAllowed();
        bankCap = _bankCap;
        maxWithdrawPerTx = _maxWithdrawPerTx;
    }

    /*/////////////////////////////////////////////////////////////
                                MODIFICADOR
    /////////////////////////////////////////////////////////////*/

    /// @notice Modificador para prevenir llamadas reentrantes
    modifier nonReentrant() {
        if (_locked != 1) revert ReentrantCall();
        _locked = 2;
        _;
        _locked = 1;
    }

    /*/////////////////////////////////////////////////////////////
                                RECEPCIÓN DE ETH
    /////////////////////////////////////////////////////////////*/

    /// @notice Maneja el envío directo de ETH al contrato, tratándolo como un depósito del remitente.
    receive() external payable {
        _deposit(msg.sender, msg.value);
    }

    /// @notice Maneja llamadas a funciones inexistentes, tratándolas como depósitos si llevan ETH.
    fallback() external payable {
        _deposit(msg.sender, msg.value);
    }


    /*/////////////////////////////////////////////////////////////
                        FUNCIONES EXTERNAL PAYABLE
    /////////////////////////////////////////////////////////////*/

    /// @notice Función principal para depositar ETH en la bóveda del remitente.
    /// @dev Utiliza el modificador `nonReentrant` y delega la lógica a la función privada `_deposit`.
    function deposit() external payable nonReentrant {
        // El check de msg.value > 0 se realiza dentro de _deposit
        _deposit(msg.sender, msg.value);
    }

    /// @notice Retira ETH de la bóveda del remitente.
    /// @param amount Monto a retirar en wei.
    function withdraw(uint256 amount) external nonReentrant {
        // Checks
        if (amount == 0) revert ZeroValueNotAllowed();
        if (amount > maxWithdrawPerTx) revert ExceedsPerTxLimit(maxWithdrawPerTx, amount);

        uint256 userBalance = vaults[msg.sender];
        if (amount > userBalance) revert InsufficientBalance(userBalance, amount);

        // Effects
        vaults[msg.sender] = userBalance - amount;
        totalBankBalance -= amount;
        withdrawCount += 1;

        // Interaction: transferencia segura
        _safeSendETH(msg.sender, amount);

        // Event
        emit Withdraw(msg.sender, amount, vaults[msg.sender]);
    }

    /*/////////////////////////////////////////////////////////////
                        FUNCIONES EXTERNAL VIEW
    /////////////////////////////////////////////////////////////*/

    /// @notice Devuelve el balance en wei de la bóveda de `account`.
    /// @param account Dirección del usuario.
    /// @return balance Balance en wei de la bóveda.
    function getVaultBalance(address account) external view returns (uint256 balance) {
        return vaults[account];
    }

    /// @notice Devuelve el balance total de ETH (wei) que el contrato posee (balance de la cuenta de contrato).
    /// @return balance Balance del contrato en wei.
    function contractBalance() external view returns (uint256 balance) {
        return address(this).balance;
    }

    /*/////////////////////////////////////////////////////////////
                            FUNCIONES PRIVADAS
    /////////////////////////////////////////////////////////////*/

    /// @dev Implementa la lógica principal de depósito, siguiendo el patrón Checks-Effects-Interactions.
    /// @param sender Dirección del depositante
    /// @param amount Monto a depositar en wei
    function _deposit(address sender, uint256 amount) private {
        // Checks
        if (amount == 0) revert ZeroValueNotAllowed();

        // Prevención de desbordamiento (overflow) al verificar el límite
        uint256 newTotal = totalBankBalance + amount;
        if (newTotal > bankCap) revert BankCapExceeded(bankCap, amount, totalBankBalance);

        // Effects
        vaults[sender] += amount;
        totalBankBalance = newTotal;
        depositCount += 1;
        depositCountPerUser[sender] += 1;

        // Event
        emit Deposit(sender, amount, vaults[sender]);
    }

    /// @dev Envía ETH de manera segura usando `call` y revierte si la llamada falla.
    /// @param to Dirección destino
    /// @param amount Monto a enviar en wei
    function _safeSendETH(address to, uint256 amount) private {
        // No hay interacciones externas antes de este punto (retirada de ETH del balance)
        // La interacción es solo la transferencia.
        (bool success, ) = to.call{value: amount}("");
        if (!success) revert TransferFailed(to, amount);
    }
}