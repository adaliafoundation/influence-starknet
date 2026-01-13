import { shortString } from 'starknet';

// Config for both local devnets and testnets
const testnetConfig = {
  Dispatcher: { isDispatcher: true, constructorArgs: { admin: '{CALLER}' } },
  Asteroid: { isContract: true, constructorArgs: {
    name: shortString.encodeShortString('Influence Asteroids'),
    symbol: shortString.encodeShortString('INFAST'),
    admin: '{CALLER}'
  }},
  Crew: { isContract: true, constructorArgs: {
    name: shortString.encodeShortString('Influence Crews'),
    symbol: shortString.encodeShortString('INFCRW'),
    admin: '{CALLER}'
  }},
  Crewmate: { isContract: true, constructorArgs: {
    name: shortString.encodeShortString('Influence Crewmates'),
    symbol: shortString.encodeShortString('INFCRM'),
    initial_token: 20000,
    admin: '{CALLER}'
  }},
  Designate: { isContract: true, constructorArgs: {} },
  Ship: { isContract: true, constructorArgs: {
    name: shortString.encodeShortString('Influence Ships'),
    symbol: shortString.encodeShortString('INFSHP'),
    admin: '{CALLER}'
  }},
  Sway: { isContract: true, constructorArgs: {
    name: shortString.encodeShortString('Standard Weighted Adalian Yield'),
    symbol: shortString.encodeShortString('SWAY'),
    decimals: 6n,
    admin: '{CALLER}'
  }},

  // Agreements
  AcceptContractAgreement: { isSystem: true },
  AcceptPrepaidMerkleAgreement: { isSystem: true },
  AcceptPrepaidAgreement: { isSystem: true },
  ExtendPrepaidAgreement: { isSystem: true },
  CancelPrepaidAgreement: { isSystem: true },
  RemoveFromWhitelist: { isSystem: true },
  RemoveAccountFromWhitelist: { isSystem: true },
  TransferPrepaidAgreement: { isSystem: true },
  Whitelist: { isSystem: true },
  WhitelistAccount: { isSystem: true },

  // Construction
  ConstructionAbandon: { isSystem: true },
  ConstructionDeconstruct: { isSystem: true },
  ConstructionFinish: { isSystem: true },
  ConstructionPlan: { isSystem: true },
  ConstructionStart: { isSystem: true },

  // Control
  CommandeerShip: { isSystem: true },
  ManageAsteroid: { isSystem: true },
  RepossessBuilding: { isSystem: true },

  // Crew
  ArrangeCrew: { isSystem: true },
  DelegateCrew: { isSystem: true },
  EjectCrew: { isSystem: true },
  ExchangeCrew: { isSystem: true },
  InitializeArvadian: { isSystem: true },
  RecruitAdalian: { isSystem: true },
  ResupplyFood: { isSystem: true },
  ResupplyFoodFromExchange: { isSystem: true },
  StationCrew: { isSystem: true },

  // Deliveries
  AcceptDelivery: { isSystem: true },
  DumpDelivery: { isSystem: true },
  CancelDelivery: { isSystem: true },
  PackageDelivery: { isSystem: true },
  ReceiveDelivery: { isSystem: true },
  SendDelivery: { isSystem: true },

  // Deposits
  SampleDepositStart: { isSystem: true },
  SampleDepositImprove: { isSystem: true },
  SampleDepositFinish: { isSystem: true },
  ListDepositForSale: { isSystem: true },
  PurchaseDeposit: { isSystem: true },
  UnlistDepositForSale: { isSystem: true },

  // Emergencies
  ActivateEmergency: { isSystem: true },
  CollectEmergencyPropellant: { isSystem: true },
  DeactivateEmergency: { isSystem: true },

  // Orders
  CreateSellOrder: { isSystem: true },
  FillSellOrder: { isSystem: true },
  CancelSellOrder: { isSystem: true },
  CreateBuyOrder: { isSystem: true },
  FillBuyOrder: { isSystem: true },

  // Policies
  AssignContractPolicy: { isSystem: true },
  AssignPrepaidMerklePolicy: { isSystem: true },
  AssignPrepaidPolicy: { isSystem: true },
  AssignPublicPolicy: { isSystem: true },
  RemoveContractPolicy: { isSystem: true },
  RemovePrepaidPolicy: { isSystem: true },
  RemovePrepaidMerklePolicy: { isSystem: true },
  RemovePublicPolicy: { isSystem: true },

  // Production
  AssembleShipFinish: { isSystem: true },
  AssembleShipStart: { isSystem: true },
  ExtractResourceFinish: { isSystem: true },
  ExtractResourceStart: { isSystem: true },
  ProcessProductsFinish: { isSystem: true },
  ProcessProductsStart: { isSystem: true },

  // Random Events
  ResolveRandomEvent: { isSystem: true },
  CheckForRandomEvent: { isSystem: true },

  // Rewards
  ClaimArrivalReward: { isSystem: true },
  ClaimPrepareForLaunchReward: { isSystem: true },
  ClaimTestnetSway: { isSystem: true },

  // Sales
  GrantAdalians: { isSystem: true },
  GrantStarterPack: { isSystem: true },
  PurchaseAdalian: { isSystem: true },
  PurchaseAsteroid: { isSystem: true },

  // Scanning
  ScanResourcesFinish: { isSystem: true },
  ScanResourcesStart: { isSystem: true },
  ScanSurfaceFinish: { isSystem: true },
  ScanSurfaceStart: { isSystem: true },

  // Seeding
  InitializeAsteroid: { isSystem: true },
  SeedAsteroids: { isSystem: true },
  SeedCrewmates: { isSystem: true },
  SeedColony: { isSystem: true },
  SeedHabitat: { isSystem: true },
  SeedOrders: { isSystem: true },

  // Ship
  DockShip: { isSystem: true },
  TransitBetweenFinish: { isSystem: true },
  TransitBetweenStart: { isSystem: true },
  UndockShip: { isSystem: true },

  // Direct Messaging
  DirectMessage: { isSystem: true },
  RekeyInbox: { isSystem: true },

  // Misc
  AnnotateEvent: { isSystem: true },
  ChangeName: { isSystem: true },
  ConfigureExchange: { isSystem: true },
  ReadComponent: { isSystem: true },
  WriteComponent: { isSystem: true }
};

export default {
  devnet: testnetConfig,
  testnet: testnetConfig,
  sepolia: testnetConfig,
  mainnet: {
    Dispatcher: { isDispatcher: true, constructorArgs: { admin: '{CALLER}' } },
    Asteroid: { isContract: true, constructorArgs: {
      name: shortString.encodeShortString('Influence Asteroids'),
      symbol: shortString.encodeShortString('INFAST'),
      admin: '{CALLER}'
    }},
    Crew: { isContract: true, constructorArgs: {
      name: shortString.encodeShortString('Influence Crews'),
      symbol: shortString.encodeShortString('INFCRW'),
      admin: '{CALLER}'
    }},
    Crewmate: { isContract: true, constructorArgs: {
      name: shortString.encodeShortString('Influence Crewmates'),
      symbol: shortString.encodeShortString('INFCRM'),
      initial_token: 20000,
      admin: '{CALLER}'
    }},
    Ship: { isContract: true, constructorArgs: {
      name: shortString.encodeShortString('Influence Ships'),
      symbol: shortString.encodeShortString('INFSHP'),
      admin: '{CALLER}'
    }},

    // Agreements
    AcceptContractAgreement: { isSystem: true },
    AcceptPrepaidMerkleAgreement: { isSystem: true },
    AcceptPrepaidAgreement: { isSystem: true },
    ExtendPrepaidAgreement: { isSystem: true },
    CancelPrepaidAgreement: { isSystem: true },
    RemoveFromWhitelist: { isSystem: true },
    RemoveAccountFromWhitelist: { isSystem: true },
    TransferPrepaidAgreement: { isSystem: true },
    Whitelist: { isSystem: true },
    WhitelistAccount: { isSystem: true },

    // Construction
    ConstructionAbandon: { isSystem: true },
    ConstructionDeconstruct: { isSystem: true },
    ConstructionFinish: { isSystem: true },
    ConstructionPlan: { isSystem: true },
    ConstructionStart: { isSystem: true },

    // Control
    CommandeerShip: { isSystem: true },
    ManageAsteroid: { isSystem: true },
    RepossessBuilding: { isSystem: true },

    // Crew
    ArrangeCrew: { isSystem: true },
    DelegateCrew: { isSystem: true },
    EjectCrew: { isSystem: true },
    ExchangeCrew: { isSystem: true },
    InitializeArvadian: { isSystem: true },
    RecruitAdalian: { isSystem: true },
    ResupplyFood: { isSystem: true },
    ResupplyFoodFromExchange: { isSystem: true },
    StationCrew: { isSystem: true },

    // Deliveries
    AcceptDelivery: { isSystem: true },
    DumpDelivery: { isSystem: true },
    CancelDelivery: { isSystem: true },
    PackageDelivery: { isSystem: true },
    ReceiveDelivery: { isSystem: true },
    SendDelivery: { isSystem: true },

    // Deposits
    SampleDepositStart: { isSystem: true },
    SampleDepositImprove: { isSystem: true },
    SampleDepositFinish: { isSystem: true },
    ListDepositForSale: { isSystem: true },
    PurchaseDeposit: { isSystem: true },
    UnlistDepositForSale: { isSystem: true },

    // Emergencies
    ActivateEmergency: { isSystem: true },
    CollectEmergencyPropellant: { isSystem: true },
    DeactivateEmergency: { isSystem: true },

    // Orders
    CreateSellOrder: { isSystem: true },
    FillSellOrder: { isSystem: true },
    CancelSellOrder: { isSystem: true },
    CreateBuyOrder: { isSystem: true },
    FillBuyOrder: { isSystem: true },

    // Policies
    AssignContractPolicy: { isSystem: true },
    AssignPrepaidMerklePolicy: { isSystem: true },
    AssignPrepaidPolicy: { isSystem: true },
    AssignPublicPolicy: { isSystem: true },
    RemoveContractPolicy: { isSystem: true },
    RemovePrepaidPolicy: { isSystem: true },
    RemovePrepaidMerklePolicy: { isSystem: true },
    RemovePublicPolicy: { isSystem: true },

    // Production
    AssembleShipFinish: { isSystem: true },
    AssembleShipStart: { isSystem: true },
    ExtractResourceFinish: { isSystem: true },
    ExtractResourceStart: { isSystem: true },
    ProcessProductsFinish: { isSystem: true },
    ProcessProductsStart: { isSystem: true },

    // Random Events
    ResolveRandomEvent: { isSystem: true },
    CheckForRandomEvent: { isSystem: true },

    // Rewards
    ClaimArrivalReward: { isSystem: true },
    ClaimPrepareForLaunchReward: { isSystem: true },
    ClaimTestnetSway: { isSystem: true },

    // Sales
    GrantAdalians: { isSystem: true },
    GrantStarterPack: { isSystem: true },
    PurchaseAdalian: { isSystem: true },
    PurchaseAsteroid: { isSystem: true },

    // Scanning
    ScanResourcesFinish: { isSystem: true },
    ScanResourcesStart: { isSystem: true },
    ScanSurfaceFinish: { isSystem: true },
    ScanSurfaceStart: { isSystem: true },

    // Seeding
    InitializeAsteroid: { isSystem: true },
    SeedAsteroids: { isSystem: true },
    SeedCrewmates: { isSystem: true },
    SeedColony: { isSystem: true },
    SeedHabitat: { isSystem: true },
    SeedOrders: { isSystem: true },

    // Ship
    DockShip: { isSystem: true },
    TransitBetweenFinish: { isSystem: true },
    TransitBetweenStart: { isSystem: true },
    UndockShip: { isSystem: true },

    // Direct Messaging
    DirectMessage: { isSystem: true },
    RekeyInbox: { isSystem: true },

    // Misc
    AnnotateEvent: { isSystem: true },
    ChangeName: { isSystem: true },
    ConfigureExchange: { isSystem: true },
    ReadComponent: { isSystem: true },
    WriteComponent: { isSystem: true }
  }
};
