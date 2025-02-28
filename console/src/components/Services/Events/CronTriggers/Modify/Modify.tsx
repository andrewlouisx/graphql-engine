import React from 'react';
import { useQueryClient } from 'react-query';
import Button from '../../../../Common/Button/Button';
import { useScheduledTrigger } from '../state';
import { ScheduledTrigger } from '../../types';
import { Dispatch } from '../../../../../types';
import { parseServerScheduledTrigger } from '../utils';
import CronTriggerFrom from '../../Common/Components/CronTriggerForm';
import { saveScheduledTrigger, deleteScheduledTrigger } from '../../ServerIO';

type Props = {
  dispatch: Dispatch;
  currentTrigger?: ScheduledTrigger;
};

const Modify: React.FC<Props> = props => {
  const { dispatch, currentTrigger } = props;
  const { state, setState } = useScheduledTrigger();
  const queryClient = useQueryClient();

  React.useEffect(() => {
    if (currentTrigger) {
      const initState = parseServerScheduledTrigger(currentTrigger);
      setState.bulk(initState);
    }
  }, [currentTrigger]);

  if (!currentTrigger) {
    return null;
  }
  const deleteFunc = () => {
    const requestCallback = () => {
      setState.loading('delete', false);
      queryClient.refetchQueries(['cronTrigger'], { active: true });
    };
    setState.loading('delete', true);
    dispatch(
      deleteScheduledTrigger(currentTrigger, requestCallback, requestCallback)
    );
  };

  const onSave = (e: React.SyntheticEvent) => {
    e.preventDefault();
    const requestCallback = () => {
      setState.loading('modify', false);
    };
    setState.loading('modify', true);
    dispatch(
      saveScheduledTrigger(
        state,
        currentTrigger,
        requestCallback,
        requestCallback
      )
    );
  };

  return (
    <div className="mb-md">
      <CronTriggerFrom state={state} setState={setState} />
      <div>
        <Button
          onClick={onSave}
          color="yellow"
          size="sm"
          disabled={state.loading.modify}
          className="mr-md"
        >
          {state.loading.modify ? 'Saving...' : 'Save'}
        </Button>
        <Button
          onClick={deleteFunc}
          color="red"
          size="sm"
          disabled={state.loading.delete}
          className="mr-md"
        >
          {state.loading.delete ? 'Deleting...' : 'Delete'}
        </Button>
      </div>
    </div>
  );
};

export default Modify;
