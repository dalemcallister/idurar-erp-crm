import '../data/models/goal.dart';

/// Built-in goal templates and their weighted rubrics (Design §6.1, F-GOAL-01/02).
/// Seeded into the database on first run; users can add custom goals/rubrics.
class GoalTemplates {
  static List<Rubric> rubrics() => [
        const Rubric(id: 'rub-discovery', name: 'Discovery call', dimensions: [
          RubricDimension(
              name: 'Listening ratio',
              weight: 0.25,
              description: 'Did you leave room for the other party to speak?'),
          RubricDimension(
              name: 'Question quality',
              weight: 0.25,
              description: 'Open, probing questions that surface needs.'),
          RubricDimension(
              name: 'Need discovery',
              weight: 0.2,
              description: 'Did you uncover the real problem and its impact?'),
          RubricDimension(
              name: 'Clarity',
              weight: 0.15,
              description: 'Clear, concise framing of value.'),
          RubricDimension(
              name: 'Call to action',
              weight: 0.15,
              description: 'A clear, agreed next step.'),
        ]),
        const Rubric(id: 'rub-negotiation', name: 'Negotiation', dimensions: [
          RubricDimension(name: 'Objection handling', weight: 0.3),
          RubricDimension(name: 'Anchoring & framing', weight: 0.2),
          RubricDimension(name: 'Listening ratio', weight: 0.2),
          RubricDimension(name: 'Empathy', weight: 0.15),
          RubricDimension(name: 'Call to action', weight: 0.15),
        ]),
        const Rubric(id: 'rub-interview', name: 'Job interview', dimensions: [
          RubricDimension(name: 'Clarity', weight: 0.3),
          RubricDimension(name: 'Structure (STAR)', weight: 0.25),
          RubricDimension(name: 'Filler-word control', weight: 0.2),
          RubricDimension(name: 'Confidence & pace', weight: 0.15),
          RubricDimension(name: 'Question quality', weight: 0.1),
        ]),
        const Rubric(
            id: 'rub-feedback',
            name: 'Difficult feedback',
            dimensions: [
              RubricDimension(name: 'Empathy', weight: 0.3),
              RubricDimension(name: 'Specificity', weight: 0.25),
              RubricDimension(name: 'Listening ratio', weight: 0.2),
              RubricDimension(name: 'Clarity', weight: 0.15),
              RubricDimension(name: 'Call to action', weight: 0.1),
            ]),
        const Rubric(id: 'rub-teaching', name: 'Teaching', dimensions: [
          RubricDimension(name: 'Clarity', weight: 0.3),
          RubricDimension(name: 'Checking for understanding', weight: 0.25),
          RubricDimension(name: 'Question quality', weight: 0.2),
          RubricDimension(name: 'Pacing', weight: 0.15),
          RubricDimension(name: 'Empathy', weight: 0.1),
        ]),
        const Rubric(id: 'rub-team', name: 'Team meeting', dimensions: [
          RubricDimension(
              name: 'Participation & inclusion',
              weight: 0.25,
              description: 'Did everyone get a voice and were people invited in?'),
          RubricDimension(
              name: 'Decisions & action items',
              weight: 0.25,
              description: 'Clear owners and next steps came out of the meeting.'),
          RubricDimension(
              name: 'Clarity',
              weight: 0.2,
              description: 'Agenda and points were clear and easy to follow.'),
          RubricDimension(
              name: 'Time management',
              weight: 0.15,
              description: 'Kept on track and to time.'),
          RubricDimension(name: 'Listening', weight: 0.15),
        ]),
      ];

  static List<Goal> goals() => const [
        Goal(
          id: 'goal-discovery',
          userId: null,
          name: 'Discovery call',
          description:
              'Uncover the prospect\'s real needs and agree a next step.',
          rubricId: 'rub-discovery',
          isTemplate: true,
        ),
        Goal(
          id: 'goal-negotiation',
          userId: null,
          name: 'Negotiation',
          description: 'Handle objections and reach a fair agreement.',
          rubricId: 'rub-negotiation',
          isTemplate: true,
        ),
        Goal(
          id: 'goal-interview',
          userId: null,
          name: 'Job interview',
          description: 'Communicate clearly and structure strong answers.',
          rubricId: 'rub-interview',
          isTemplate: true,
        ),
        Goal(
          id: 'goal-feedback',
          userId: null,
          name: 'Difficult feedback',
          description: 'Deliver hard feedback with empathy and specificity.',
          rubricId: 'rub-feedback',
          isTemplate: true,
        ),
        Goal(
          id: 'goal-teaching',
          userId: null,
          name: 'Teaching',
          description: 'Explain clearly and check for understanding.',
          rubricId: 'rub-teaching',
          isTemplate: true,
        ),
        Goal(
          id: 'goal-team',
          userId: null,
          name: 'Team meeting',
          description:
              'Run an effective, inclusive team meeting with clear decisions '
              'and action items.',
          rubricId: 'rub-team',
          isTemplate: true,
        ),
      ];
}
