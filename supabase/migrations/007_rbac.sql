-- ============================================================================
-- CSIS SmartAssist — Application RBAC
-- ============================================================================

CREATE TABLE public.roles (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL UNIQUE,
    description TEXT NOT NULL DEFAULT '',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE public.permissions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL UNIQUE,
    description TEXT NOT NULL DEFAULT '',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE public.role_permissions (
    role_id UUID NOT NULL REFERENCES public.roles(id) ON DELETE CASCADE,
    permission_id UUID NOT NULL REFERENCES public.permissions(id) ON DELETE CASCADE,
    PRIMARY KEY (role_id, permission_id)
);

CREATE TABLE public.user_roles (
    user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    role_id UUID NOT NULL REFERENCES public.roles(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (user_id, role_id)
);

CREATE INDEX idx_user_roles_role_id ON public.user_roles(role_id);
CREATE INDEX idx_role_permissions_permission_id ON public.role_permissions(permission_id);

INSERT INTO public.roles (name, description) VALUES
    ('student', 'Normal SmartAssist user'),
    ('faculty', 'Faculty SmartAssist user'),
    ('booking_admin', 'Booking and room administrator'),
    ('content_admin', 'Department content and RAG administrator'),
    ('department_admin', 'Broad department administrator'),
    ('super_admin', 'Full SmartAssist administrator')
ON CONFLICT (name) DO NOTHING;

INSERT INTO public.permissions (name, description) VALUES
    ('faculty.read', 'View faculty information'),
    ('faculty.write', 'Manage faculty information'),
    ('projects.read', 'View project information'),
    ('projects.write', 'Manage project information'),
    ('department.read', 'View department information'),
    ('department.write', 'Manage department information'),
    ('rag.read', 'View RAG content and status'),
    ('rag.write', 'Synchronize and modify RAG content'),
    ('bookings.read', 'View own bookings'),
    ('bookings.read_all', 'View all user bookings'),
    ('bookings.create', 'Create bookings'),
    ('bookings.approve', 'Approve bookings'),
    ('bookings.reject', 'Reject bookings'),
    ('rooms.read', 'View rooms'),
    ('rooms.write', 'Manage rooms'),
    ('users.read', 'View users'),
    ('users.roles.manage', 'Assign and remove application roles')
ON CONFLICT (name) DO NOTHING;

WITH role_permissions_seed(role_name, permission_name) AS (
    VALUES
        ('student', 'department.read'), ('student', 'bookings.read'),
        ('student', 'bookings.create'), ('student', 'rooms.read'),
        ('faculty', 'department.read'), ('faculty', 'faculty.read'),
        ('faculty', 'projects.read'), ('faculty', 'bookings.read'),
        ('faculty', 'bookings.create'), ('faculty', 'rooms.read'),
        ('booking_admin', 'department.read'), ('booking_admin', 'bookings.read'),
        ('booking_admin', 'bookings.read_all'), ('booking_admin', 'bookings.approve'),
        ('booking_admin', 'bookings.reject'), ('booking_admin', 'rooms.read'),
        ('booking_admin', 'rooms.write'),
        ('content_admin', 'department.read'), ('content_admin', 'department.write'),
        ('content_admin', 'rag.read'), ('content_admin', 'rag.write'),
        ('department_admin', 'department.read'), ('department_admin', 'department.write'),
        ('department_admin', 'rag.read'), ('department_admin', 'rag.write'),
        ('department_admin', 'bookings.read'), ('department_admin', 'bookings.read_all'),
        ('department_admin', 'bookings.approve'), ('department_admin', 'bookings.reject'),
        ('department_admin', 'rooms.read'), ('department_admin', 'rooms.write'),
        ('super_admin', 'faculty.read'), ('super_admin', 'faculty.write'),
        ('super_admin', 'projects.read'), ('super_admin', 'projects.write'),
        ('super_admin', 'department.read'), ('super_admin', 'department.write'),
        ('super_admin', 'rag.read'), ('super_admin', 'rag.write'),
        ('super_admin', 'bookings.read'), ('super_admin', 'bookings.read_all'),
        ('super_admin', 'bookings.create'), ('super_admin', 'bookings.approve'),
        ('super_admin', 'bookings.reject'), ('super_admin', 'rooms.read'),
        ('super_admin', 'rooms.write'), ('super_admin', 'users.read'),
        ('super_admin', 'users.roles.manage')
)
INSERT INTO public.role_permissions (role_id, permission_id)
SELECT r.id, p.id
FROM role_permissions_seed seed
JOIN public.roles r ON r.name = seed.role_name
JOIN public.permissions p ON p.name = seed.permission_name
ON CONFLICT DO NOTHING;

-- Preserve legacy administrators as full application administrators.
INSERT INTO public.user_roles (user_id, role_id)
SELECT p.id, r.id
FROM public.profiles p
JOIN public.roles r ON r.name = 'super_admin'
WHERE p.is_admin = TRUE
ON CONFLICT DO NOTHING;

INSERT INTO public.user_roles (user_id, role_id)
SELECT p.id, r.id
FROM public.profiles p
JOIN public.roles r ON r.name = 'student'
WHERE NOT EXISTS (
    SELECT 1 FROM public.user_roles ur WHERE ur.user_id = p.id
)
ON CONFLICT DO NOTHING;

CREATE OR REPLACE FUNCTION public.assign_default_student_role()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    INSERT INTO public.user_roles (user_id, role_id)
    SELECT NEW.id, r.id FROM public.roles r WHERE r.name = 'student'
    ON CONFLICT DO NOTHING;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_profile_created_assign_student_role ON public.profiles;
CREATE TRIGGER on_profile_created_assign_student_role
    AFTER INSERT ON public.profiles
    FOR EACH ROW EXECUTE FUNCTION public.assign_default_student_role();

CREATE OR REPLACE FUNCTION public.user_has_permission(required_permission TEXT)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM public.user_roles ur
        JOIN public.role_permissions rp ON rp.role_id = ur.role_id
        JOIN public.permissions p ON p.id = rp.permission_id
        WHERE ur.user_id = auth.uid()
          AND p.name = required_permission
    );
$$;

-- Replace the legacy is_admin policies from earlier migrations. The column is
-- retained only for the data migration above and backwards compatibility.
DROP POLICY IF EXISTS "Admins can view all profiles" ON public.profiles;
DROP POLICY IF EXISTS "Admins can manage all bookings" ON public.bookings;
DROP POLICY IF EXISTS "Admins can manage rag_files" ON public.rag_files;
DROP POLICY IF EXISTS "Admins can manage rag_chunks" ON public.rag_chunks;
DROP POLICY IF EXISTS "Admins can manage rooms" ON public.rooms;

CREATE POLICY "Users with users.read can view all profiles"
    ON public.profiles FOR SELECT USING (public.user_has_permission('users.read'));
CREATE POLICY "Users with bookings.read_all can manage bookings"
    ON public.bookings FOR ALL USING (public.user_has_permission('bookings.read_all'))
    WITH CHECK (public.user_has_permission('bookings.read_all'));
CREATE POLICY "Users with rag.write can manage rag_files"
    ON public.rag_files FOR ALL USING (public.user_has_permission('rag.write'))
    WITH CHECK (public.user_has_permission('rag.write'));
CREATE POLICY "Users with rag.write can manage rag_chunks"
    ON public.rag_chunks FOR ALL USING (public.user_has_permission('rag.write'))
    WITH CHECK (public.user_has_permission('rag.write'));
CREATE POLICY "Users with rooms.write can manage rooms"
    ON public.rooms FOR ALL USING (public.user_has_permission('rooms.write'))
    WITH CHECK (public.user_has_permission('rooms.write'));

ALTER TABLE public.roles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.permissions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.role_permissions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_roles ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Authenticated users can read roles"
    ON public.roles FOR SELECT USING (auth.role() = 'authenticated');
CREATE POLICY "Authenticated users can read permissions"
    ON public.permissions FOR SELECT USING (auth.role() = 'authenticated');
CREATE POLICY "Authenticated users can read role permissions"
    ON public.role_permissions FOR SELECT USING (auth.role() = 'authenticated');
CREATE POLICY "Users can view their own roles"
    ON public.user_roles FOR SELECT USING (auth.uid() = user_id);

-- profiles.is_admin remains only as a migration compatibility column. Remove it
-- after all deployments and operational scripts no longer depend on it.