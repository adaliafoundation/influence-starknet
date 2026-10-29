export const missionDefinitions = {
  version: 2,
  observerPolicy: 'MissionObserver',
  observationTargets: { maxGroups: 8, encoding: '[campaign, packedSubject + missionMask * 2^80] per group', candidateFields: ['campaign', 'subject.label', 'subject.id', 'mission'] },
  swayDecimals: 6,
  colonization: {
    campaignConstant: 'COLONIZATION_CAMPAIGN',
    subject: 'ASTEROID',
    missions: [
      { id: 0, name: 'Claim a New World', reward: '150000000000' },
      { id: 1, name: 'Build a Habitat', reward: '250000000000' },
      { id: 2, name: 'Connect the Colony', reward: '300000000000' },
      { id: 3, name: 'Establish Commerce', reward: '350000000000' },
      { id: 4, name: 'Found a Colony', reward: '450000000000' }
    ],
    evidenceSlots: {
      Colonizer: 'original enrolled account', ScanStarted: 'pending scan fingerprint',
      ScanFinished: 'successful surface scan completion timestamp', Earned: 'bits 0..3: scan, habitat, spaceport, marketplace',
      1: 'qualifying used Habitat ID', 2: 'qualifying used Spaceport ID', 3: 'qualifying used Marketplace ID'
    },
    observedSystems: ['ScanSurfaceStart', 'ScanSurfaceFinish', 'ConstructionStart', 'ConstructionFinish', 'StationCrew', 'DockShip', 'FillBuyOrder', 'FillSellOrder']
  },
  starter: {
    campaignConstant: 'STARTER_MISSION_CAMPAIGN', subject: 'CREW',
    observedSystems: ['ConstructionPlan', 'ConstructionStart', 'ConstructionFinish', 'SampleDepositStart', 'SampleDepositFinish', 'ExtractResourceStart', 'ExtractResourceFinish', 'ProcessProductsStart', 'ProcessProductsFinish', 'SendDelivery', 'ReceiveDelivery', 'ResupplyFood', 'FillSellOrder']
  },
  lifecycleEvents: ['MissionAccepted', 'MissionCompleted', 'MissionRewardClaimed'],
  contracts: ['Dispatcher', 'MissionObserver', 'StarterMissionCampaign', 'ColonizationMissionCampaign', 'RegisterMissionCampaign', 'UpgradeMissionCampaign', 'ConfigureStarterMissions', 'ConfigureColonizationMissions', 'MigrateStarterObserver', 'AcceptMission', 'MissionValidate', 'ReadMissionState', 'ClaimMissionReward']
};
