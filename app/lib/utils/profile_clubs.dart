import '../models/tournament.dart';

typedef ProfileClubGroups = ({List<Club> managed, List<Club> joined});

ProfileClubGroups groupProfileClubs(Iterable<Club> clubs) {
  return (
    managed: clubs.where((club) => club.isOwner).toList(growable: false),
    joined: clubs
        .where(
          (club) => club.isApproved && club.isMember && !club.isOwner,
        )
        .toList(growable: false),
  );
}
