import { InjectedRouter, withRouter } from 'react-router';
import { AddNativeQuery } from './AddNativeQuery';
import { RouteWrapper } from '../components/RouteWrapper';

export const AddNativeQueryRoute = withRouter<{
  location: Location;
  router: InjectedRouter;
}>(({ location, router }) => {
  return (
    <RouteWrapper pathname={location.pathname} push={router.push}>
      <AddNativeQuery push={router.push} />
    </RouteWrapper>
  );
});