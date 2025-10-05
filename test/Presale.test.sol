// SPDX-License-Identifier: MIT

pragma solidity 0.8.28;

import "forge-std/Test.sol";
import "../src/Presale.sol";
import "./mocks/MockSaleToken.sol";
import "./mocks/ReceiverMock.sol";

contract MockFailReceiver {
    receive() external payable {
        revert("I reject ETH");
    }
}


contract PresaleTest is Test {
    Presale public presale;
    MockSaleToken public saleToken;
    
    // Direcciones reales de Arbitrum One
    address public constant USDT_ARBITRUM = 0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9; 
    address public constant USDC_ARBITRUM = 0xaf88d065e77c8cC2239327C5EDb3A432268e5831; 
    address public constant ETH_USD_FEED = 0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612; 
    
    address internal owner;
    address internal user1;
    address internal fundsReceiver;
    uint256 internal maxSellingAmount;
    uint256 internal startingTime;
    uint256 internal endingTime;
    uint256[][3] internal phases;


    event TokenBuy(address buyer, uint256 amount);

    function setUp() public {
        // Hacer fork de Arbitrum One
        vm.createSelectFork(vm.envString("ARBITRUM_RPC_URL"));
        
        owner = makeAddr("owner");
        user1 = makeAddr("user1");

        ReceiverMock receiver = new ReceiverMock();
        fundsReceiver = payable(address(receiver));


        saleToken = new MockSaleToken("SaleToken", "SALE");

        // supply máximo que vamos a vender
        maxSellingAmount = 1_000_000e18;

        // Mint al owner (el que luego hará approve al Presale)
        saleToken.mint(owner, maxSellingAmount);

        startingTime = block.timestamp + 1 days;
        endingTime   = startingTime + 30 days;

        // Configuración de las fases
        // Cada fase tiene un array con: [precio (USD*1e6), max tokens a vender en la fase]
        phases[0] = [300_000e18, 50_000, startingTime + 10 days];  // Fase 1: 0.05 USD, 300,000 tokens
        phases[1] = [300_000e18, 70_000, startingTime + 20 days];  // Fase 2: 0.07 USD, 300,000 tokens
        phases[2] = [400_000e18, 10_000, endingTime]; // Fase 3: 0.10 USD, 400,000 tokens
    }
    

    function testConstructorSetsStateCorrectly() public {
        // 1) El owner aprueba al address futuro
        vm.startPrank(owner);
        address futurePresale_ = vm.computeCreateAddress(owner, vm.getNonce(owner));
        saleToken.approve(futurePresale_, maxSellingAmount);

        // 2) Desplegar el contrato
        presale = new Presale(
            address(saleToken),
            USDT_ARBITRUM,
            USDC_ARBITRUM,
            fundsReceiver,
            ETH_USD_FEED,
            maxSellingAmount,
            startingTime,
            endingTime,
            phases
        );
        vm.stopPrank();

        // 3) Comprobar que todo quedó bien
        // Direcciones
        assertEq(presale.saleTokenAddress(), address(saleToken));
        assertEq(presale.usdtAddress(), USDT_ARBITRUM);
        assertEq(presale.usdcAddress(), USDC_ARBITRUM);
        assertEq(presale.fundsReceiverAddress(), fundsReceiver);

        // Parámetros
        assertEq(presale.maxSellingAmount(), maxSellingAmount);
        assertEq(presale.startingTime(), startingTime);
        assertEq(presale.endingTime(), endingTime);

        // El contrato debe tener todos los tokens
        assertEq(saleToken.balanceOf(address(presale)), maxSellingAmount);

        // Contadores iniciales
        assertEq(presale.totalSold(), 0);
        assertEq(presale.currentPhase(), 0);
    }

    function testConstructorRevertsIfTimesAreWrong() public {
        vm.startPrank(owner);
        address futurePresale_ = vm.computeCreateAddress(owner, vm.getNonce(owner));
        saleToken.approve(futurePresale_, maxSellingAmount);

        // endingTime <= startingTime
        vm.expectRevert("Incorrect presale times");
        new Presale(
            address(saleToken),
            USDT_ARBITRUM,
            USDC_ARBITRUM,
            fundsReceiver,
            ETH_USD_FEED,
            maxSellingAmount,
            startingTime,
            startingTime - 1,
            phases
        );
        vm.stopPrank();
    }

    function testConstructorRevertsWithoutAllowance() public {
        MockSaleToken badToken = new MockSaleToken("BadToken", "BAD");
        badToken.mint(owner, maxSellingAmount);

        uint256 startingTime_ = block.timestamp + 1 days;
        uint256 endingTime_ = startingTime_ + 30 days;

        
        vm.startPrank(owner);

        vm.expectRevert();
        new Presale(
            address(badToken),
            USDT_ARBITRUM,
            USDC_ARBITRUM,
            fundsReceiver,
            ETH_USD_FEED,
            maxSellingAmount,
            startingTime_,
            endingTime_,
            phases
        );

        vm.stopPrank();
    }

    function testConstructorRevertsInsufficientBalance() public {
        MockSaleToken badToken = new MockSaleToken("BadToken", "BAD");
        badToken.mint(owner, maxSellingAmount - 1e18);

        uint256 startingTime_ = block.timestamp + 1 days;
        uint256 endingTime_ = startingTime_ + 30 days;

        
        vm.startPrank(owner);
        address futurePresale_ = vm.computeCreateAddress(owner, vm.getNonce(owner));
        badToken.approve(futurePresale_, maxSellingAmount);

        vm.expectRevert();
        new Presale(
            address(badToken),
            USDT_ARBITRUM,
            USDC_ARBITRUM,
            fundsReceiver,
            ETH_USD_FEED,
            maxSellingAmount,
            startingTime_,
            endingTime_,
            phases
        );

        vm.stopPrank();
    }

    function testBuyWithStableRevertsWhenBlacklisted() public {
        vm.startPrank(owner);
        address futurePresale_ = vm.computeCreateAddress(owner, vm.getNonce(owner));
        saleToken.approve(futurePresale_, maxSellingAmount);
        presale = new Presale(
            address(saleToken),
            USDT_ARBITRUM,
            USDC_ARBITRUM,
            fundsReceiver,
            ETH_USD_FEED,
            maxSellingAmount,
            startingTime,
            endingTime,
            phases
        );

        presale.addToBlackList(user1);
        vm.stopPrank();

        vm.startPrank(user1);
        vm.warp(startingTime + 1); // Avanzar al inicio de la preventa
        vm.expectRevert("User is blacklisted");
        presale.buyWithStable(USDT_ARBITRUM, 100e6);
        vm.stopPrank();
    }

    function testBuyWithStableRevertsPresaleIsNotStarted() public {
        vm.startPrank(owner);
        address futurePresale_ = vm.computeCreateAddress(owner, vm.getNonce(owner));
        saleToken.approve(futurePresale_, maxSellingAmount);
        presale = new Presale(
            address(saleToken),
            USDT_ARBITRUM,
            USDC_ARBITRUM,
            fundsReceiver,
            ETH_USD_FEED,
            maxSellingAmount,
            startingTime,
            endingTime,
            phases
        );

        vm.stopPrank();

        vm.startPrank(user1);
        vm.warp(startingTime - 1); // Antes del inicio de la preventa
        vm.expectRevert("Presale is not active");
        presale.buyWithStable(USDT_ARBITRUM, 100e6);
        vm.stopPrank();
    }

    function testBuyWithStableRevertsPresaleIsEnded() public {
        vm.startPrank(owner);
        address futurePresale_ = vm.computeCreateAddress(owner, vm.getNonce(owner));
        saleToken.approve(futurePresale_, maxSellingAmount);
        presale = new Presale(
            address(saleToken),
            USDT_ARBITRUM,
            USDC_ARBITRUM,
            fundsReceiver,
            ETH_USD_FEED,
            maxSellingAmount,
            startingTime,
            endingTime,
            phases
        );

        vm.stopPrank();

        vm.startPrank(user1);
        vm.warp(endingTime + 1); // Despues del final de la preventa
        vm.expectRevert("Presale is not active");
        presale.buyWithStable(USDT_ARBITRUM, 100e6);
        vm.stopPrank();
    }

    function testBuyWithStableRevertsInvalidStable() public {
        vm.startPrank(owner);
        address futurePresale_ = vm.computeCreateAddress(owner, vm.getNonce(owner));
        saleToken.approve(futurePresale_, maxSellingAmount);
        presale = new Presale(
            address(saleToken),
            USDT_ARBITRUM,
            USDC_ARBITRUM,
            fundsReceiver,
            ETH_USD_FEED,
            maxSellingAmount,
            startingTime,
            endingTime,
            phases
        );

        vm.stopPrank();

        // 3) Crear un token inválido
        MockSaleToken fakeStable = new MockSaleToken("FakeUSD", "FUSD");

        vm.startPrank(user1);
        vm.warp(startingTime + 1); // Despues del inicio de la preventa
        vm.expectRevert("Invalid stable coin");
        presale.buyWithStable(address(fakeStable), 100e6);
        vm.stopPrank();
    }


    function testBuyWithStableAdvancesPhaseByThreshold() public {
        vm.startPrank(owner);
        address futurePresale_ = vm.computeCreateAddress(owner, vm.getNonce(owner));
        saleToken.approve(futurePresale_, maxSellingAmount);
        presale = new Presale(
            address(saleToken),
            USDT_ARBITRUM,
            USDC_ARBITRUM,
            fundsReceiver,
            ETH_USD_FEED,
            maxSellingAmount,
            startingTime,
            endingTime,
            phases
        );

        vm.stopPrank();

        vm.warp(startingTime + 1); // Despues del inicio de la preventa

        // 3) Dar USDC a user1
        // Precio actual en la fase 0
        uint256 price_ = phases[0][1]; // 50_000 (0.05 USDC)

        // Queremos justo pasar el threshold
        uint256 threshold_ = phases[0][0]; // 300_000e18

        // Compra = threshold + 1 token
        uint256 tokenToBuy_ = threshold_ + 1e18;

        // Resolver backwards: amount = tokens * price / 1e6 / 1e12
        uint256 payAmount_ = tokenToBuy_ * price_ / 1e6 / 1e12;

        deal(USDC_ARBITRUM, user1, payAmount_);

        vm.startPrank(user1);
        
        IERC20(USDC_ARBITRUM).approve(address(presale), payAmount_);
        presale.buyWithStable(USDC_ARBITRUM, payAmount_);

        vm.stopPrank();

        // Comprobar que avanzó de fase
        assertEq(presale.currentPhase(), 1);
    }

    function testBuyWithStableAdvancesPhaseByDeadline() public {
    vm.startPrank(owner);
    address futurePresale_ = vm.computeCreateAddress(owner, vm.getNonce(owner));
    saleToken.approve(futurePresale_, maxSellingAmount);
    presale = new Presale(
        address(saleToken),
        USDT_ARBITRUM,
        USDC_ARBITRUM,
        fundsReceiver,
        ETH_USD_FEED,
        maxSellingAmount,
        startingTime,
        endingTime,
        phases
    );
    vm.stopPrank();

    // Avanzar el tiempo justo después del fin de la primera fase
    vm.warp(phases[0][2] + 1);

    // Hacer una compra pequeña
    uint256 payAmount_ = 10e6;
    deal(USDC_ARBITRUM, user1, payAmount_);
    vm.startPrank(user1);
    IERC20(USDC_ARBITRUM).approve(address(presale), payAmount_);
    presale.buyWithStable(USDC_ARBITRUM, payAmount_);
    vm.stopPrank();

    assertEq(presale.currentPhase(), 1);
}


    function testBuyWithStableRevertsExceedingMaxSupply() public {
        // Desplegar Presale
        vm.startPrank(owner);
        address futurePresale_ = vm.computeCreateAddress(owner, vm.getNonce(owner));
        saleToken.approve(futurePresale_, maxSellingAmount);
        Presale presale_ = new Presale(
            address(saleToken),
            USDT_ARBITRUM,
            USDC_ARBITRUM,
            fundsReceiver,
            ETH_USD_FEED,
            maxSellingAmount,
            startingTime,
            endingTime,
            phases
        );
        vm.stopPrank();

        // Ir más allá del deadline de la fase 0
        vm.warp(startingTime + 1);

        // Dar USDC a user1
        uint256 price_ = phases[0][1]; // precio en la fase 0
        uint256 payAmount_ = (maxSellingAmount + 1e18) * price_ / 1e18;
        deal(USDC_ARBITRUM, user1, payAmount_);
        vm.startPrank(user1);
        IERC20(USDC_ARBITRUM).approve(address(presale_), payAmount_);

        // Comprar
        vm.expectRevert("Exceeds max selling amount");
        presale_.buyWithStable(USDC_ARBITRUM, payAmount_);
        vm.stopPrank();
    }

    function testBuyWithStableTransfersStableAndUpdatesState() public {
        // 1) Deploy Presale
        vm.startPrank(owner);
        address futurePresale_ = vm.computeCreateAddress(owner, vm.getNonce(owner));
        saleToken.approve(futurePresale_, maxSellingAmount);
        Presale presale_ = new Presale(
            address(saleToken),
            USDT_ARBITRUM,
            USDC_ARBITRUM,
            fundsReceiver,
            ETH_USD_FEED,
            maxSellingAmount,
            startingTime,
            endingTime,
            phases
        );
        vm.stopPrank();

        // 2) Dentro de la venta
        vm.warp(startingTime + 1);

        // 3) User1 tiene USDC
        uint256 payAmount_ = 100e6; // 100 USDC
        deal(USDC_ARBITRUM, user1, payAmount_);

        // 4) Approve del user1 al presale
        vm.startPrank(user1);
        IERC20(USDC_ARBITRUM).approve(address(presale_), payAmount_);

        // 5) Balance inicial del fundsReceiver
        uint256 beforeBalance_ = IERC20(USDC_ARBITRUM).balanceOf(fundsReceiver);

        // 6) Esperar evento
        vm.expectEmit(true, true, false, true);
        emit TokenBuy(user1, payAmount_);

        // 7) Ejecutar compra
        presale_.buyWithStable(USDC_ARBITRUM, payAmount_);
        vm.stopPrank();

        // 8) Comprobar balances
        assertEq(IERC20(USDC_ARBITRUM).balanceOf(fundsReceiver), beforeBalance_ + payAmount_);
        assertEq(IERC20(USDC_ARBITRUM).balanceOf(user1), 0);

        // 9) Comprobar que userTokenBalance se actualizó
        uint256 expectedTokens = payAmount_ * 1e12 * 1e6 / phases[0][1];
        assertEq(presale_.userTokenBalance(user1), expectedTokens);

        // 10) Comprobar que totalSold también se incrementó
        assertEq(presale_.totalSold(), expectedTokens);
    }


    function testBuyWithEtherRevertsWhenBlacklisted() public {
        // 1) Deploy Presale
        vm.startPrank(owner);
        address futurePresale_ = vm.computeCreateAddress(owner, vm.getNonce(owner));
        saleToken.approve(futurePresale_, maxSellingAmount);
        Presale presale_ = new Presale(
            address(saleToken),
            USDT_ARBITRUM,
            USDC_ARBITRUM,
            fundsReceiver,
            ETH_USD_FEED,
            maxSellingAmount,
            startingTime,
            endingTime,
            phases
        );
        vm.stopPrank();

        // 2) Owner mete al user en blacklist
        vm.prank(owner);
        presale_.addToBlackList(user1);

        // 3) Dar ETH al user
        vm.deal(user1, 10 ether);

        // 4) Esperar revert
        vm.startPrank(user1);
        vm.expectRevert(bytes("User is blacklisted"));
        presale_.buyWithEther{value: 1 ether}();
        vm.stopPrank();
    }

    function testBuyWithEtherRevertsBeforeStart() public {
        // 1) Deploy Presale
        vm.startPrank(owner);
        address futurePresale_ = vm.computeCreateAddress(owner, vm.getNonce(owner));
        saleToken.approve(futurePresale_, maxSellingAmount);
        Presale presale_ = new Presale(
            address(saleToken),
            USDT_ARBITRUM,
            USDC_ARBITRUM,
            fundsReceiver,
            ETH_USD_FEED,
            maxSellingAmount,
            startingTime,
            endingTime,
            phases
        );
        vm.stopPrank();

        // 2) Tiempo antes del inicio
        vm.warp(startingTime - 1);

        // 3) Dar ETH al user
        vm.deal(user1, 10 ether);

        // 4) Esperar revert
        vm.startPrank(user1);
        vm.expectRevert(bytes("Presale is not active"));
        presale_.buyWithEther{value: 1 ether}();
        vm.stopPrank();
    }


    function testBuyWithEtherRevertsAfterEnd() public {
        // 1) Deploy Presale
        vm.startPrank(owner);
        address futurePresale_ = vm.computeCreateAddress(owner, vm.getNonce(owner));
        saleToken.approve(futurePresale_, maxSellingAmount);
        Presale presale_ = new Presale(
            address(saleToken),
            USDT_ARBITRUM,
            USDC_ARBITRUM,
            fundsReceiver,
            ETH_USD_FEED,
            maxSellingAmount,
            startingTime,
            endingTime,
            phases
        );
        vm.stopPrank();

        // 2) Tiempo después del final
        vm.warp(endingTime + 1);

        // 3) Dar ETH al user
        vm.deal(user1, 10 ether);

        // 4) Esperar revert
        vm.startPrank(user1);
        vm.expectRevert(bytes("Presale is not active"));
        presale_.buyWithEther{value: 1 ether}();
        vm.stopPrank();
    }

    function testBuyWithEtherRevertsWhenExceedsMaxSupply() public {
        // 1) Deploy Presale
        vm.startPrank(owner);
        address futurePresale_ = vm.computeCreateAddress(owner, vm.getNonce(owner));
        saleToken.approve(futurePresale_, maxSellingAmount);
        Presale presale_ = new Presale(
            address(saleToken),
            USDT_ARBITRUM,
            USDC_ARBITRUM,
            fundsReceiver,
            ETH_USD_FEED,
            maxSellingAmount,
            startingTime,
            endingTime,
            phases
        );
        vm.stopPrank();

        // 2) Warp dentro de la venta
        vm.warp(startingTime + 1);

        // 3) Obtener precio actual de ETH/USD
        uint256 ethPrice = presale_.getEtherPrice(); // feed de Chainlink

        // 4) Calcular cuánto ETH excede el supply
        uint256 price_ = phases[0][1]; // precio de fase 0
        uint256 minUsdNeeded = (maxSellingAmount + 1e18) * price_ / 1e6; // en USD (6 decimales)
        uint256 ethNeeded = (minUsdNeeded * 1e18) / ethPrice; // en ETH

        // 5) Dar ETH al user
        vm.deal(user1, ethNeeded);

        // 6) Esperar revert
        vm.startPrank(user1);
        vm.expectRevert(bytes("Exceeds max selling amount"));
        presale_.buyWithEther{value: ethNeeded}();
        vm.stopPrank();
    }

    function testBuyWithEtherRevertsOnTransferFail() public {
        // 1) Deploy MockFailReceiver
        MockFailReceiver badReceiver_ = new MockFailReceiver();

        // 2) Deploy Presale con el badReceiver como fundsReceiver
        vm.startPrank(owner);
        address futurePresale_ = vm.computeCreateAddress(owner, vm.getNonce(owner));
        saleToken.approve(futurePresale_, maxSellingAmount);
        Presale presale_ = new Presale(
            address(saleToken),
            USDT_ARBITRUM,
            USDC_ARBITRUM,
            address(badReceiver_), // 👈 receptor que siempre falla
            ETH_USD_FEED,
            maxSellingAmount,
            startingTime,
            endingTime,
            phases
        );
        vm.stopPrank();

        // 3) Warp dentro de la venta
        vm.warp(startingTime + 1);

        // 4) Dar ETH a user1
        vm.deal(user1, 1 ether);

        // 5) Expect revert
        vm.startPrank(user1);
        vm.expectRevert(bytes("Transfer fail"));
        presale_.buyWithEther{value: 1 ether}();
        vm.stopPrank();
    }

    function testBuyWithEtherTransfersETHAndUpdatesState() public {
        // 1) Deploy fundsReceiver mock
        fundsReceiver = address(new ReceiverMock());

        // 2) Deploy Presale con el mock
        vm.startPrank(owner);
        address futurePresale_ = vm.computeCreateAddress(owner, vm.getNonce(owner));
        saleToken.approve(futurePresale_, maxSellingAmount);
        Presale presale_ = new Presale(
            address(saleToken),
            USDT_ARBITRUM,
            USDC_ARBITRUM,
            fundsReceiver,
            ETH_USD_FEED,
            maxSellingAmount,
            startingTime,
            endingTime,
            phases
        );
        vm.stopPrank();

        // 3) Avanzamos tiempo dentro de la preventa
        vm.warp(startingTime + 1);

        // 4) Dar ETH a user1
        vm.deal(user1, 10 ether);

        // 5) Guardar balance inicial del fundsReceiver
        uint256 beforeBalance = fundsReceiver.balance;

        // 6) Calcular expected tokens
        uint256 ethPrice = presale_.getEtherPrice();
        uint256 usdValue = 1 ether * ethPrice / 1e18;
        uint256 expectedTokens = usdValue * 1e6 / phases[0][1];

        // 7) Ejecutar compra
        vm.startPrank(user1);
        vm.expectEmit(true, true, false, true);
        emit TokenBuy(user1, expectedTokens);
        presale_.buyWithEther{value: 1 ether}();
        vm.stopPrank();

        // 8) Comprobar que el fundsReceiver recibió el ETH
        assertEq(fundsReceiver.balance, beforeBalance + 1 ether);

        // 9) Comprobar que el user tiene los tokens registrados
        assertEq(presale_.userTokenBalance(user1), expectedTokens);

        // 10) Comprobar que totalSold aumentó igual
        assertEq(presale_.totalSold(), expectedTokens);
    }

    function testClaimRevertsBeforeEnd() public {
        // 1) Deploy Presale
        vm.startPrank(owner);
        address futurePresale_ = vm.computeCreateAddress(owner, vm.getNonce(owner));
        saleToken.approve(futurePresale_, maxSellingAmount);
        Presale presale_ = new Presale(
            address(saleToken),
            USDT_ARBITRUM,
            USDC_ARBITRUM,
            fundsReceiver,
            ETH_USD_FEED,
            maxSellingAmount,
            startingTime,
            endingTime,
            phases
        );
        vm.stopPrank();

        // 2) Avanzar dentro de la venta
        vm.warp(startingTime + 1);

        // 3) Dar USDC al user1 para comprar
        uint256 payAmount_ = 100e6; // 100 USDC
        deal(USDC_ARBITRUM, user1, payAmount_);

        vm.startPrank(user1);
        IERC20(USDC_ARBITRUM).approve(address(presale_), payAmount_);
        presale_.buyWithStable(USDC_ARBITRUM, payAmount_);

        // 4) Intentar reclamar ANTES del endingTime
        vm.expectRevert(bytes("Presale not ended"));
        presale_.claim();
        vm.stopPrank();
    }


    function testClaimTransfersTokensAndClearsBalance() public {
        // 1) Deploy Presale
        vm.startPrank(owner);
        address futurePresale_ = vm.computeCreateAddress(owner, vm.getNonce(owner));
        saleToken.approve(futurePresale_, maxSellingAmount);
        Presale presale_ = new Presale(
            address(saleToken),
            USDT_ARBITRUM,
            USDC_ARBITRUM,
            fundsReceiver,
            ETH_USD_FEED,
            maxSellingAmount,
            startingTime,
            endingTime,
            phases
        );
        vm.stopPrank();

        // 2) Avanzar dentro de la venta
        vm.warp(startingTime + 1);

        // 3) Dar USDC al user1 y comprar tokens
        uint256 payAmount_ = 100e6; // 100 USDC
        deal(USDC_ARBITRUM, user1, payAmount_);

        vm.startPrank(user1);
        IERC20(USDC_ARBITRUM).approve(address(presale_), payAmount_);
        presale_.buyWithStable(USDC_ARBITRUM, payAmount_);
        vm.stopPrank();

        // 4) Avanzar tiempo más allá del endingTime
        vm.warp(endingTime + 1);

        // 5) Calcular tokens esperados
        uint256 expectedTokens_ = payAmount_ * 1e12 * 1e6 / phases[0][1];

        // 6) Balances antes del claim
        uint256 beforeUserBalance_ = saleToken.balanceOf(user1);
        uint256 beforeContractBalance_ = saleToken.balanceOf(address(presale_));

        // 7) Ejecutar claim
        vm.prank(user1);
        presale_.claim();

        // 8) Verificar que el user recibió los tokens
        assertEq(saleToken.balanceOf(user1), beforeUserBalance_ + expectedTokens_);

        // 9) Verificar que el contrato perdió esos tokens
        assertEq(saleToken.balanceOf(address(presale_)), beforeContractBalance_ - expectedTokens_);

        // 10) Verificar que el balance interno del usuario se limpió
        assertEq(presale_.userTokenBalance(user1), 0);
    }

    function testEmergencyERC20WithdrawRevertsIfNotOwner() public {
        // 1) Deploy Presale
        vm.startPrank(owner);
        address futurePresale_ = vm.computeCreateAddress(owner, vm.getNonce(owner));
        saleToken.approve(futurePresale_, maxSellingAmount);
        Presale presale_ = new Presale(
            address(saleToken),
            USDT_ARBITRUM,
            USDC_ARBITRUM,
            fundsReceiver,
            ETH_USD_FEED,
            maxSellingAmount,
            startingTime,
            endingTime,
            phases
        );
        vm.stopPrank();

        // 2) Intentar llamar desde otro usuario
        vm.startPrank(user1);
        vm.expectRevert(
            abi.encodeWithSelector(
                bytes4(keccak256("OwnableUnauthorizedAccount(address)")),
                user1
            )
        );

        presale_.emergencyERC20Withdraw(USDC_ARBITRUM, 1e6);
        vm.stopPrank();
    }


    function testEmergencyERC20WithdrawTransfersTokensToOwner() public {
        // 1️⃣ Deploy Presale normalmente
        vm.startPrank(owner);
        address futurePresale_ = vm.computeCreateAddress(owner, vm.getNonce(owner));
        saleToken.approve(futurePresale_, maxSellingAmount);
        Presale presale_ = new Presale(
            address(saleToken),
            USDT_ARBITRUM,
            USDC_ARBITRUM,
            fundsReceiver,
            ETH_USD_FEED,
            maxSellingAmount,
            startingTime,
            endingTime,
            phases
        );

        // 2️⃣ Simular que el contrato recibió tokens ERC20 (p. ej. USDC)
        uint256 stuckAmount_ = 100e6; // 100 USDC
        deal(USDC_ARBITRUM, address(presale_), stuckAmount_); // dar tokens al contrato

        // 3️⃣ Balance inicial del owner
        uint256 beforeBalance_ = IERC20(USDC_ARBITRUM).balanceOf(owner);

        // 4️⃣ Owner ejecuta la función de emergencia
        presale_.emergencyERC20Withdraw(USDC_ARBITRUM, stuckAmount_);

        // 5️⃣ Comprobar balances
        uint256 afterOwnerBalance_ = IERC20(USDC_ARBITRUM).balanceOf(owner);
        uint256 afterContractBalance_ = IERC20(USDC_ARBITRUM).balanceOf(address(presale_));

        assertEq(afterOwnerBalance_, beforeBalance_ + stuckAmount_, "Owner did not receive tokens");
        assertEq(afterContractBalance_, 0, "Contract should have no tokens left");

        vm.stopPrank();
    }

    function testEmergencyETHWithdrawTransfersETHToOwner() public {
        // 1️⃣ Deploy Presale
        vm.startPrank(owner);
        address futurePresale = vm.computeCreateAddress(owner, vm.getNonce(owner));
        saleToken.approve(futurePresale, maxSellingAmount);
        Presale presale_ = new Presale(
            address(saleToken),
            USDT_ARBITRUM,
            USDC_ARBITRUM,
            fundsReceiver,
            ETH_USD_FEED,
            maxSellingAmount,
            startingTime,
            endingTime,
            phases
        );
        vm.stopPrank(); // ✅ cerramos el prank antes de enviar ETH

        // 2️⃣ Mandar ETH al contrato (simular ETH bloqueado)
        vm.deal(address(presale_), 2 ether);

        // 3️⃣ Guardar balances iniciales
        uint256 beforeOwnerBalance = owner.balance;
        uint256 beforeContractBalance = address(presale_).balance;
        assertEq(beforeContractBalance, 2 ether, "Contrato no tiene ETH inicial");

        // 4️⃣ Ejecutar el withdraw como owner
        vm.startPrank(owner); // ✅ ahora sí, contexto limpio
        presale_.emergencyETHWithdraw();
        vm.stopPrank();

        // 5️⃣ Comprobar que el owner recibió el ETH
        uint256 afterOwnerBalance = owner.balance;
        uint256 afterContractBalance = address(presale_).balance;

        assertEq(
            afterOwnerBalance,
            beforeOwnerBalance + 2 ether,
            "Owner did not receive ETH"
        );
        assertEq(afterContractBalance, 0, "Contract still has ETH");
    }


    function testEmergencyETHWithdrawRevertsIfNotOwner() public {
        // 1️⃣ Deploy Presale
        vm.startPrank(owner);
        address futurePresale_ = vm.computeCreateAddress(owner, vm.getNonce(owner));
        saleToken.approve(futurePresale_, maxSellingAmount);
        Presale presale_ = new Presale(
            address(saleToken),
            USDT_ARBITRUM,
            USDC_ARBITRUM,
            fundsReceiver,
            ETH_USD_FEED,
            maxSellingAmount,
            startingTime,
            endingTime,
            phases
        );
        vm.stopPrank();

        // 2️⃣ Simular que el contrato tiene ETH bloqueado
        vm.deal(address(presale_), 1 ether);

        // 3️⃣ Intentar llamar desde un usuario no autorizado
        vm.startPrank(user1);
        vm.expectRevert(
            abi.encodeWithSelector(
                bytes4(keccak256("OwnableUnauthorizedAccount(address)")),
                user1
            )
        );
        presale_.emergencyETHWithdraw();
        vm.stopPrank();
    }


    function testBuyWithStableWith18DecimalsWorks() public {
        MockStableToken18 stable18 = new MockStableToken18();
        vm.startPrank(owner);
        saleToken.approve(vm.computeCreateAddress(owner, vm.getNonce(owner)), maxSellingAmount);
        Presale presale_ = new Presale(
            address(saleToken),
            address(stable18),
            USDC_ARBITRUM,
            fundsReceiver,
            ETH_USD_FEED,
            maxSellingAmount,
            startingTime,
            endingTime,
            phases
        );
        vm.stopPrank();

        vm.warp(startingTime + 1);
        vm.startPrank(user1);
        stable18.mint(user1, 100e18);
        stable18.approve(address(presale_), 100e18);
        presale_.buyWithStable(address(stable18), 100e18);
        vm.stopPrank();
    }

    function testGetEtherPriceReturnsNonZero() public {
        // 1️⃣ Deploy del contrato
        vm.startPrank(owner);
        address futurePresale = vm.computeCreateAddress(owner, vm.getNonce(owner));
        saleToken.approve(futurePresale, maxSellingAmount);
        Presale presale_ = new Presale(
            address(saleToken),
            USDT_ARBITRUM,
            USDC_ARBITRUM,
            fundsReceiver,
            ETH_USD_FEED, // ✅ Chainlink feed real de Arbitrum
            maxSellingAmount,
            startingTime,
            endingTime,
            phases
        );
        vm.stopPrank();

        // 2️⃣ Llamar a getEtherPrice
        uint256 price = presale_.getEtherPrice();

        // 3️⃣ Asegurar que devuelve un valor válido (>0 y en rango realista)
        assertGt(price, 0, "Price must be greater than zero");
        assertLt(price, 10_000e18, "Price out of expected range"); // < $10k ETH
    }

    function testCheckCurrentPhaseAdvancesWhenBothConditionsTrue() public {
        vm.startPrank(owner);
        address futurePresale = vm.computeCreateAddress(owner, vm.getNonce(owner));
        saleToken.approve(futurePresale, maxSellingAmount);
        Presale presale_ = new Presale(
            address(saleToken),
            USDT_ARBITRUM,
            USDC_ARBITRUM,
            fundsReceiver,
            ETH_USD_FEED,
            maxSellingAmount,
            startingTime,
            endingTime,
            phases
        );
        vm.stopPrank();

        // Simular estar justo después de la primera fase y ya vender casi el threshold
        vm.warp(phases[0][2] + 1);
        deal(USDC_ARBITRUM, user1, 10e6);

        vm.startPrank(user1);
        IERC20(USDC_ARBITRUM).approve(address(presale_), 10e6);
        presale_.buyWithStable(USDC_ARBITRUM, 10e6);
        vm.stopPrank();

        // Debe haber avanzado de fase
        assertEq(presale_.currentPhase(), 1);
    }

    function testEmergencyETHWithdrawSucceedsWithEOA() public {
        // Owner es un EOA (no contrato)
        vm.startPrank(owner);
        address futurePresale = vm.computeCreateAddress(owner, vm.getNonce(owner));
        saleToken.approve(futurePresale, maxSellingAmount);
        Presale presale_ = new Presale(
            address(saleToken),
            USDT_ARBITRUM,
            USDC_ARBITRUM,
            owner, // ✅ fundsReceiver es EOA
            ETH_USD_FEED,
            maxSellingAmount,
            startingTime,
            endingTime,
            phases
        );
        vm.stopPrank();

        vm.deal(address(presale_), 1 ether);
        uint256 before = owner.balance;

        vm.prank(owner);
        presale_.emergencyETHWithdraw();

        assertEq(owner.balance, before + 1 ether, "Owner did not receive ETH");
    }


    function testRemoveBlackListRemovesUser() public {
        vm.startPrank(owner);
        address futurePresale = vm.computeCreateAddress(owner, vm.getNonce(owner));
        saleToken.approve(futurePresale, maxSellingAmount);
        Presale presale_ = new Presale(
            address(saleToken),
            USDT_ARBITRUM,
            USDC_ARBITRUM,
            fundsReceiver,
            ETH_USD_FEED,
            maxSellingAmount,
            startingTime,
            endingTime,
            phases
        );
        
        presale_.addToBlackList(user1);
        assertTrue(presale_.blackList(user1));
        
        presale_.removeBlackList(user1);
        assertFalse(presale_.blackList(user1));
        vm.stopPrank();
    }

    function testRemoveBlackListRevertsIfNotOwner() public {
        vm.startPrank(owner);
        address futurePresale = vm.computeCreateAddress(owner, vm.getNonce(owner));
        saleToken.approve(futurePresale, maxSellingAmount);
        Presale presale_ = new Presale(
            address(saleToken),
            USDT_ARBITRUM,
            USDC_ARBITRUM,
            fundsReceiver,
            ETH_USD_FEED,
            maxSellingAmount,
            startingTime,
            endingTime,
            phases
        );
        vm.stopPrank();
        
        vm.startPrank(user1);
        vm.expectRevert(
            abi.encodeWithSelector(
                bytes4(keccak256("OwnableUnauthorizedAccount(address)")),
                user1
            )
        );
        presale_.removeBlackList(user1);
        vm.stopPrank();
    }

    function testClaimWithZeroBalanceDoesNothing() public {
        vm.startPrank(owner);
        address futurePresale = vm.computeCreateAddress(owner, vm.getNonce(owner));
        saleToken.approve(futurePresale, maxSellingAmount);
        Presale presale_ = new Presale(
            address(saleToken),
            USDT_ARBITRUM,
            USDC_ARBITRUM,
            fundsReceiver,
            ETH_USD_FEED,
            maxSellingAmount,
            startingTime,
            endingTime,
            phases
        );
        vm.stopPrank();
        
        vm.warp(endingTime + 1);
        
        uint256 beforeBalance = saleToken.balanceOf(user1);
        vm.prank(user1);
        presale_.claim();
        
        assertEq(saleToken.balanceOf(user1), beforeBalance);
        assertEq(presale_.userTokenBalance(user1), 0);
    }

    function testCheckCurrentPhaseDoesNotExceedPhase2() public {
        vm.startPrank(owner);
        address futurePresale = vm.computeCreateAddress(owner, vm.getNonce(owner));
        saleToken.approve(futurePresale, maxSellingAmount);
        Presale presale_ = new Presale(
            address(saleToken),
            USDT_ARBITRUM,
            USDC_ARBITRUM,
            fundsReceiver,
            ETH_USD_FEED,
            maxSellingAmount,
            startingTime,
            endingTime,
            phases
        );
        vm.stopPrank();
        
        // 1️⃣ Primero, avanzar a fase 1 con una compra pequeña
        vm.warp(phases[0][2] + 1);
        deal(USDC_ARBITRUM, user1, 10e6);
        vm.startPrank(user1);
        IERC20(USDC_ARBITRUM).approve(address(presale_), 10e6);
        presale_.buyWithStable(USDC_ARBITRUM, 10e6);
        vm.stopPrank();
        
        assertEq(presale_.currentPhase(), 1, "Should be in phase 1");
        
        // 2️⃣ Ahora avanzar a fase 2 con otra compra
        vm.warp(phases[1][2] + 1);
        deal(USDC_ARBITRUM, user1, 10e6);
        vm.startPrank(user1);
        IERC20(USDC_ARBITRUM).approve(address(presale_), 10e6);
        presale_.buyWithStable(USDC_ARBITRUM, 10e6);
        vm.stopPrank();
        
        assertEq(presale_.currentPhase(), 2, "Should be in phase 2");
        
        // 3️⃣ Hacer una compra más y verificar que NO avanza a "fase 3"
        uint256 payAmount = 100e6;
        deal(USDC_ARBITRUM, user1, payAmount);
        vm.startPrank(user1);
        IERC20(USDC_ARBITRUM).approve(address(presale_), payAmount);
        presale_.buyWithStable(USDC_ARBITRUM, payAmount);
        vm.stopPrank();
        
        // Debe seguir en fase 2
        assertEq(presale_.currentPhase(), 2, "Should still be in phase 2");
    }

    function testCheckCurrentPhaseDoesNotAdvanceWhenConditionsNotMet() public {
        vm.startPrank(owner);
        address futurePresale = vm.computeCreateAddress(owner, vm.getNonce(owner));
        saleToken.approve(futurePresale, maxSellingAmount);
        Presale presale_ = new Presale(
            address(saleToken),
            USDT_ARBITRUM,
            USDC_ARBITRUM,
            fundsReceiver,
            ETH_USD_FEED,
            maxSellingAmount,
            startingTime,
            endingTime,
            phases
        );
        vm.stopPrank();
        
        // Avanzar dentro de la fase 0, pero sin llegar al deadline
        vm.warp(startingTime + 1);
        
        // Hacer una compra pequeña que NO alcance el threshold de fase 0
        uint256 payAmount = 10e6; // 10 USDC - mucho menos que el threshold
        deal(USDC_ARBITRUM, user1, payAmount);
        
        vm.startPrank(user1);
        IERC20(USDC_ARBITRUM).approve(address(presale_), payAmount);
        presale_.buyWithStable(USDC_ARBITRUM, payAmount);
        vm.stopPrank();
        
        // Verificar que sigue en fase 0
        assertEq(presale_.currentPhase(), 0, "Should still be in phase 0");
    }

    function testBuyWithStableWith6DecimalsUsesCorrectFormula() public {
        vm.startPrank(owner);
        address futurePresale = vm.computeCreateAddress(owner, vm.getNonce(owner));
        saleToken.approve(futurePresale, maxSellingAmount);
        Presale presale_ = new Presale(
            address(saleToken),
            USDT_ARBITRUM,
            USDC_ARBITRUM,
            fundsReceiver,
            ETH_USD_FEED,
            maxSellingAmount,
            startingTime,
            endingTime,
            phases
        );
        vm.stopPrank();

        vm.warp(startingTime + 1);
        
        uint256 payAmount = 100e6; // 100 USDC (6 decimales)
        deal(USDC_ARBITRUM, user1, payAmount);
        
        uint256 expectedTokens = payAmount * 10**(18 - 6) * 1e6 / phases[0][1];
        
        vm.startPrank(user1);
        IERC20(USDC_ARBITRUM).approve(address(presale_), payAmount);
        presale_.buyWithStable(USDC_ARBITRUM, payAmount);
        vm.stopPrank();
        
        assertEq(presale_.userTokenBalance(user1), expectedTokens);
    }

    function testBuyWithStableAtExactStartTime() public {
        vm.startPrank(owner);
        address futurePresale = vm.computeCreateAddress(owner, vm.getNonce(owner));
        saleToken.approve(futurePresale, maxSellingAmount);
        Presale presale_ = new Presale(
            address(saleToken),
            USDT_ARBITRUM,
            USDC_ARBITRUM,
            fundsReceiver,
            ETH_USD_FEED,
            maxSellingAmount,
            startingTime,
            endingTime,
            phases
        );
        vm.stopPrank();

        // Exactamente en el startingTime (no +1)
        vm.warp(startingTime);
        
        uint256 payAmount = 100e6;
        deal(USDC_ARBITRUM, user1, payAmount);
        
        vm.startPrank(user1);
        IERC20(USDC_ARBITRUM).approve(address(presale_), payAmount);
        presale_.buyWithStable(USDC_ARBITRUM, payAmount);
        vm.stopPrank();
        
        assertGt(presale_.userTokenBalance(user1), 0);
    }

    function testBuyWithStableAtExactEndTime() public {
        vm.startPrank(owner);
        address futurePresale = vm.computeCreateAddress(owner, vm.getNonce(owner));
        saleToken.approve(futurePresale, maxSellingAmount);
        Presale presale_ = new Presale(
            address(saleToken),
            USDT_ARBITRUM,
            USDC_ARBITRUM,
            fundsReceiver,
            ETH_USD_FEED,
            maxSellingAmount,
            startingTime,
            endingTime,
            phases
        );
        vm.stopPrank();

        // Exactamente en el endingTime (no +1)
        vm.warp(endingTime);
        
        uint256 payAmount = 100e6;
        deal(USDC_ARBITRUM, user1, payAmount);
        
        vm.startPrank(user1);
        IERC20(USDC_ARBITRUM).approve(address(presale_), payAmount);
        presale_.buyWithStable(USDC_ARBITRUM, payAmount);
        vm.stopPrank();
        
        assertGt(presale_.userTokenBalance(user1), 0);
    }

    function testEmergencyETHWithdrawSucceedsWithContractOwner() public {
        // Desplegar un contrato que será el owner
        OwnerContractMock ownerContract = new OwnerContractMock();
        
        // El owner original (que tiene tokens) debe transferir tokens al ownerContract
        vm.prank(owner);
        saleToken.transfer(address(ownerContract), maxSellingAmount);
        
        // Usar vm.prank para hacer approve desde el ownerContract
        vm.startPrank(address(ownerContract));
        address futurePresale = vm.computeCreateAddress(address(ownerContract), vm.getNonce(address(ownerContract)));
        
        // Aprobar directamente con prank
        saleToken.approve(futurePresale, maxSellingAmount);
        
        Presale presale_ = new Presale(
            address(saleToken),
            USDT_ARBITRUM,
            USDC_ARBITRUM,
            fundsReceiver,
            ETH_USD_FEED,
            maxSellingAmount,
            startingTime,
            endingTime,
            phases
        );
        vm.stopPrank();
        
        // Dar ETH al contrato Presale
        vm.deal(address(presale_), 1 ether);
        
        uint256 beforeBalance = address(ownerContract).balance;
        
        // Ejecutar withdraw desde el contrato owner
        vm.prank(address(ownerContract));
        presale_.emergencyETHWithdraw();
        
        assertEq(address(ownerContract).balance, beforeBalance + 1 ether);
        assertEq(address(presale_).balance, 0);
    }

    function testEmergencyETHWithdrawDoesNotRevertOnSuccess() public {
        vm.startPrank(owner);
        address futurePresale = vm.computeCreateAddress(owner, vm.getNonce(owner));
        saleToken.approve(futurePresale, maxSellingAmount);
        Presale presale_ = new Presale(
            address(saleToken),
            USDT_ARBITRUM,
            USDC_ARBITRUM,
            fundsReceiver,
            ETH_USD_FEED,
            maxSellingAmount,
            startingTime,
            endingTime,
            phases
        );
        vm.stopPrank();

        vm.deal(address(presale_), 5 ether);
        
        // Usar vm.expectCall para verificar que la llamada se hace correctamente
        vm.expectCall(owner, 5 ether, "");
        
        vm.prank(owner);
        presale_.emergencyETHWithdraw(); // NO debe revertir
        
        assertEq(address(presale_).balance, 0);
    }
}


contract MockStableToken18 is ERC20 {
    constructor() ERC20("MockStable18", "MUSD") {}
    function decimals() public pure override returns (uint8) {
        return 18;
    }
    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }
}


contract OwnerContractMock {
    receive() external payable {}
}