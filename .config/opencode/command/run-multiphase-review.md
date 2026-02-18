---
description: Dispatch parallel subagent code reviews, resolve conflicts between reviewers, then organize feedback into actionable buckets
---

Please dispatch @testing-guru, @nick-isms, @semver-nag, and @allocation-nag
subagents to perform parallel code reviews of any files from the last three
commits that contain changes. This will be the first pass of reviews.

Once you get their reviews, identify any points of conflict between the
subagents' reviews. Once identified, please again prompt the relevant subagent
to see how it would respond to said conflict with the other agents'
recommendation. If needed, get @measurement-guru involved and encourage
back-of-the-envelope experiments. And if there are no points of conflict, you
may skip this step.

Then, once conflicts are resolved, we enter the second review phase, where you
organize the collected feedback into three buckets:

1. Low-hanging fruit that can safely be implemented without my input. These are
   the easy wins and tiny bug fixes that would be foolhardy _not_ to address.
2. Fixes that I should provide yes or no input on.
3. Fixes that would benefit from a more extensive discussion and may require a
   refactor.

Once you've organized all feedback into these buckets, I'd like you to dispatch
new subagents to address the low-hanging fruit in bucket 1. No input from me
needed. Then, I'd like you to write the issues in buckets 2 and 3 into a
markdown proposal document that I can review.

During this review process it's important that neither you nor the subagents
pull any punches or otherwise truncate feedback. We have all the time in the
world to address issues and shouldn't kick the can on anything. Critically, you
should not unilaterally decide on whether to defer or share any issues from the
subagents — all raised issues should be placed in buckets without interference.

$ARGUMENTS
