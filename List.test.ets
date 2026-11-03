import abilityTest from './Ability.test';
import agentRepositoryTest from './AgentRepository.test';
import localUnitTest from '../../../test/LocalUnit.test';

export default function testsuite() {
  abilityTest();
  localUnitTest();
  agentRepositoryTest();
}
