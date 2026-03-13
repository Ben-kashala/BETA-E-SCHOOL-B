export type UserRole =
  | 'ADMIN'
  | 'TEACHER'
  | 'PARENT'
  | 'STUDENT'
  | 'ACCOUNTANT'
  | 'DISCIPLINE_OFFICER'
  | 'PROMOTER'

export interface User {
  id: number
  username: string
  email: string
  first_name: string
  last_name: string
  middle_name?: string | null
  phone?: string
  role: UserRole
  school?: School
  profile_picture?: string
  is_verified: boolean
  is_active: boolean
}

export interface School {
  id: number
  name: string
  code: string
  address: string
  city: string
  country: string
  phone: string
  email: string
  logo?: string
}

export interface Student {
  id: number
  user: User
  student_id: string
  school_class?: SchoolClass
  parent?: User
  enrollment_date: string
  academic_year: string
}

export interface SchoolClass {
  id: number
  name: string
  level: string
  grade: string
  section?: string
  capacity: number
  academic_year: string
}

export interface Subject {
  id: number
  name: string
  code: string
  description?: string
}

export interface Grade {
  id: number
  student: Student
  subject: Subject
  academic_year: string
  term: 'T1' | 'T2' | 'T3'
  continuous_assessment: number
  exam_score?: number
  total_score: number
}

export interface Attendance {
  id: number
  student: Student
  school_class: SchoolClass
  date: string
  status: 'PRESENT' | 'ABSENT' | 'LATE' | 'EXCUSED'
  subject?: Subject
}

export interface Assignment {
  id: number
  title: string
  description: string
  subject: Subject
  school_class: SchoolClass
  due_date: string
  total_points: number
  is_published: boolean
}

export interface Course {
  id: number
  title: string
  description: string
  subject: Subject
  school_class: SchoolClass
  content: string
  video_url?: string
  is_published: boolean
}

export interface Quiz {
  id: number
  title: string
  description?: string
  subject: Subject
  school_class: SchoolClass
  total_points: number
  time_limit?: number
  start_date: string
  end_date: string
  is_published: boolean
}

export interface Payment {
  id: number
  payment_id: string
  user: User
  student?: Student
  amount: number
  currency: string
  payment_method: string
  status: string
  payment_date?: string
}

export interface Notification {
  id: number
  title: string
  message: string
  notification_type: string
  is_read: boolean
  created_at: string
}

export interface Meeting {
  id: number
  title: string
  description: string
  meeting_date: string
  video_link?: string
  status: string
  teacher: any
  parent?: any
  student?: Student
}
