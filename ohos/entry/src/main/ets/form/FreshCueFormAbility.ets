import { Want } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { formBindingData, FormExtensionAbility, formInfo, formProvider } from '@kit.FormKit';

const STORE_NAME = 'freshcue_form';
const STORE_KEY = 'data';

export default class FreshCueFormAbility extends FormExtensionAbility {
  onAddForm(_want: Want): formBindingData.FormBindingData {
    return formBindingData.createFormBindingData(this.loadData());
  }

  onUpdateForm(formId: string): void {
    this.refresh(formId);
  }

  onAcquireFormState(_want: Want): formInfo.FormState {
    return formInfo.FormState.READY;
  }

  private async refresh(formId: string): Promise<void> {
    try {
      await formProvider.updateForm(
        formId,
        formBindingData.createFormBindingData(this.loadData()),
      );
    } catch (_e) {
      // The next scheduled refresh or app-driven update retries safely.
    }
  }

  private loadData(): Record<string, Object> {
    const fallback: Record<string, Object> = {
      'count': 0,
      'card0Title': '', 'card0Time': '', 'card0Uri': 'freshcue://archive',
      'card1Title': '', 'card1Time': '', 'card1Uri': 'freshcue://archive',
      'card2Title': '', 'card2Time': '', 'card2Uri': 'freshcue://archive',
      'card3Title': '', 'card3Time': '', 'card3Uri': 'freshcue://archive',
    };
    try {
      const store = preferences.getPreferencesSync(this.context, { name: STORE_NAME });
      const raw = store.getSync(STORE_KEY, '') as string;
      if (raw.length === 0) return fallback;
      return JSON.parse(raw) as Record<string, Object>;
    } catch (_e) {
      return fallback;
    }
  }
}
